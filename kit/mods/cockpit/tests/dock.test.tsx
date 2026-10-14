import { expect, mock, test } from 'claude-code/testing'

import { wrapLines } from '../hooks/register'

const DOCK = { title: 'Agent Dock', isFocused: true, bodyColumns: 56, placement: 'dock' as const, scroll: { offset: 0, bodyRows: 40 }, view: {} }
const DESC = 'Revisar el flujo de checkout completo'
// Over two lines even at 66 columns, so every width exercises the fold.
const LONG = 'Revisar a fondo el flujo de checkout, precios y red con tres subagentes en paralelo, dejar un informe con evidencias por cada hallazgo y proponer el orden de arreglo con su coste estimado'

type Agent = { id: string; description: string; type: string; status: string }
const AGENTS: Agent[] = [
  { id: 'a1', description: DESC, type: 'general', status: 'running' },
  { id: 'a2', description: 'Contar ficheros', type: 'general', status: 'completed' },
  { id: 'a3', description: 'Auditar red', type: 'general', status: 'failed' },
  { id: 'a4', description: 'Medir latencia', type: 'general', status: 'killed' },
  { id: 'a5', description: 'Leer la spec', type: 'general', status: 'pending' },
]

async function mountDock($: never, on: never, bodyColumns: number, mission?: string, list: Agent[] = AGENTS) {
  const $$ = $ as any, o = on as any
  const clock = mock.clock(o)
  o('agent.list', () => ({ value: list }))
  o('session.start', () => ({ cwd: '/tmp' }))
  o('command.register', () => ({ value: undefined }))
  o('ui.open', () => ({ value: { isPlaced: true } }))
  o('prompt.submit', (_: unknown, e: { text: string }) => ({ text: e.text }))
  await $$.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  if (mission) await $$.prompt.submit({ text: mission, wait: false, origin: { kind: 'composer' } })
  await clock.advance(1500)
  // A mounted drawing is a snapshot: after the clock moves, mount again to see the new state.
  const mount = () => $$.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: { ...DOCK, bodyColumns } })
  return { ui: await mount(), clock, mount }
}
// Text has no key: a mission line is found by its own text.
const missionLine = (ui: any, text: string) => ui.find({ type: 'Text', text })

// The first dock shipped green on prop checks while the real terminal wrapped: measure the drawn text.
for (const bodyColumns of [24, 30, 44, 56, 66]) {
  test(`dock a ${bodyColumns}: las cuatro secciones con su cuenta, cada agente en su sitio, misión en dos líneas que caben`, async ($, on) => {
    const { ui } = await mountDock($ as never, on as never, bodyColumns, LONG)
    expect(await ui.find({ text: 'Agent Dock' })).toBeTruthy()
    for (const key of ['team-1', 'team-3', 'team-10', 'team-0']) expect(await ui.find({ key })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'Trabajando · 1' })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'En cola · 1' })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'Parados · 2' })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'Hechos · 1' })).toBeTruthy()
    for (const key of ['a1', 'a2', 'a3', 'a4', 'a5']) expect(await ui.find({ key })).toBeTruthy()
    expect(await ui.find({ text: /● T1/ })).toBeTruthy()
    expect(await ui.find({ text: /arrancando…/ })).toBeTruthy()
    expect(await ui.find({ text: /✗ T3/ })).toBeTruthy()
    expect(await ui.find({ text: /falló/ })).toBeTruthy()
    expect(await ui.find({ text: /■ T4/ })).toBeTruthy()
    expect(await ui.find({ text: /detenido/ })).toBeTruthy()
    expect(await ui.find({ text: /○ T5/ })).toBeTruthy()
    expect(await ui.find({ text: /✓ T2/ })).toBeTruthy()
    const lines = wrapLines(LONG, bodyColumns)
    expect(lines.length).toBeGreaterThan(2)
    expect((await missionLine(ui, lines[0]!)).text).toBe(lines[0])
    const l2 = await ui.find({ type: 'Text', text: new RegExp(`^${lines[1]!.slice(0, 8).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`) })
    expect(l2.text.length).toBeLessThanOrEqual(bodyColumns)
    expect(l2.text.endsWith('…')).toBe(true)
    expect(await missionLine(ui, lines[2]!)).toBeFalsy()
  })
}

test('dock: «más» despliega la misión entera y «menos» la pliega; una misión nueva nace plegada', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 30, LONG)
  const lines = wrapLines(LONG, 30)
  expect(lines.length).toBeGreaterThan(2)
  const last = lines[lines.length - 1]!
  expect((await ui.find({ key: 'mission' })).text).toContain('más')
  await ui.press({ key: 'mission' })
  expect((await ui.find({ key: 'mission' })).text).toContain('menos')
  expect((await missionLine(ui, last)).text).toBe(last)
  await ui.press({ key: 'mission' })
  expect(await missionLine(ui, last)).toBeFalsy()
  await ui.press({ key: 'mission' })
  await ($ as any).prompt.submit({ text: LONG, wait: false, origin: { kind: 'composer' } })
  expect(await missionLine(ui, last)).toBeFalsy()
})

test('dock: una misión que cabe en dos líneas no lleva botón', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 56, 'Revisar el checkout')
  expect((await missionLine(ui, 'Revisar el checkout')).text).toBe('Revisar el checkout')
  expect(await ui.find({ key: 'mission' })).toBeFalsy()
})

test('dock: un agente sin herramienta en 2 min pasa a Parados con su tiempo sin actividad', async ($, on) => {
  const first = await mountDock($ as never, on as never, 56, undefined, AGENTS.slice(0, 1))
  expect(await first.ui.find({ type: 'Text', text: 'Trabajando · 1' })).toBeTruthy()
  // The poll runs every 1.5 s: 123 s leaves the last tick past the 120 s threshold.
  await first.clock.advance(123_000)
  await first.ui.unmount()
  const ui = await first.mount()
  expect(await ui.find({ type: 'Text', text: 'Trabajando · 0' })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: 'Parados · 1' })).toBeTruthy()
  expect(await ui.find({ text: /◌ T1/ })).toBeTruthy()
  expect(await ui.find({ text: /2:0\d sin actividad/ })).toBeTruthy()
})

test('dock: un estado que el mod no conoce sigue saliendo, bajo Trabajando', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 56, undefined, [{ id: 'x1', description: 'Arrancar', type: 'general', status: 'starting' }])
  expect(await ui.find({ type: 'Text', text: 'Trabajando · 1' })).toBeTruthy()
  expect(await ui.find({ key: 'x1' })).toBeTruthy()
  expect(await ui.find({ text: '● LIVE' })).toBeTruthy()
})

test('dock: Hechos enseña los últimos 8 y cuenta el resto', async ($, on) => {
  const many = Array.from({ length: 11 }, (_, i) => ({ id: `d${i}`, description: `Tarea ${i}`, type: 'general', status: 'completed' }))
  const { ui } = await mountDock($ as never, on as never, 56, undefined, many)
  expect(await ui.find({ type: 'Text', text: 'Hechos · 11' })).toBeTruthy()
  expect(await ui.findAll({ type: 'Text', text: /✓ T\d+/ })).toHaveLength(8)
  expect(await ui.find({ text: /… y 3 más/ })).toBeTruthy()
})

test('dock: una notificación de tarea no pisa la misión de la persona', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 56, 'Revisar el checkout')
  await ($ as any).prompt.submit({ text: '<task-notification>done</task-notification>', wait: false, origin: { kind: 'task-notification' } })
  expect(await ui.find({ text: /task-notification/ })).toBeFalsy()
  expect(await ui.find({ text: /Revisar el checkout/ })).toBeTruthy()
})

test('wrapLines envuelve por palabras, parte las largas y nunca pasa del ancho', () => {
  expect(wrapLines('aaa bbbb cc', 5)).toEqual(['aaa', 'bbbb', 'cc'])
  expect(wrapLines('abcdefgh ij', 3)).toEqual(['abc', 'def', 'gh', 'ij'])
  expect(wrapLines('uno dos', 20)).toEqual(['uno dos'])
  for (const w of [24, 30, 66]) for (const l of wrapLines(LONG, w)) expect(l.length).toBeLessThanOrEqual(w)
})
