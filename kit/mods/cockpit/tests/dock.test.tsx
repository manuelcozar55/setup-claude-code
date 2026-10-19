import { expect, mock, test } from 'claude-code/testing'

import { elapsed, wrapLines } from '../hooks/register'

const DOCK = { title: 'Agent Dock', isFocused: true, bodyColumns: 56, placement: 'dock' as const, scroll: { offset: 0, bodyRows: 40 }, view: {} }
const DESC = 'Revisar el flujo de checkout completo'
// Over one line at every width tested, so every width exercises the fold.
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
  test(`dock a ${bodyColumns}: las cuatro secciones con su cuenta, cada agente en su sitio, misión plegada en una línea que cabe`, async ($, on) => {
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
    const folded = await ui.find({ type: 'Text', text: /^Revisar a fondo.*…$/ })
    expect(folded.text.length).toBeLessThanOrEqual(bodyColumns)
    expect(await missionLine(ui, wrapLines(LONG, bodyColumns)[1]!)).toBeFalsy()
    expect((await ui.find({ key: 'mission' })).text).toContain('más')
    // The running agent's time carries its units, whatever the width.
    expect(await ui.find({ type: 'Text', text: /^\d+s$/ })).toBeTruthy()
  })
}

test('dock: «más» despliega la misión entera y «menos» la pliega; una misión nueva nace plegada', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 30, LONG)
  const lines = wrapLines(LONG, 30)
  expect(lines.length).toBeGreaterThan(1)
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

test('dock: una misión que cabe en una línea no lleva botón', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 56, 'Revisar el checkout')
  expect((await missionLine(ui, 'Revisar el checkout')).text).toBe('Revisar el checkout')
  expect(await ui.find({ key: 'mission' })).toBeFalsy()
})

test('dock: una misión de solo dos líneas también nace plegada', async ($, on) => {
  const two = 'Revisar el checkout y la red de pagos'
  expect(wrapLines(two, 24)).toHaveLength(2)
  const { ui } = await mountDock($ as never, on as never, 24, two)
  expect((await ui.find({ key: 'mission' })).text).toContain('más')
  expect((await ui.find({ type: 'Text', text: /^Revisar el checkout y l…$/ })).text).toHaveLength(24)
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
  expect(await ui.find({ text: /2m0\ds sin actividad/ })).toBeTruthy()
})

test('dock: un estado que el mod no conoce sigue saliendo, bajo Trabajando', async ($, on) => {
  const { ui } = await mountDock($ as never, on as never, 56, undefined, [{ id: 'x1', description: 'Arrancar', type: 'general', status: 'starting' }])
  expect(await ui.find({ type: 'Text', text: 'Trabajando · 1' })).toBeTruthy()
  expect(await ui.find({ key: 'x1' })).toBeTruthy()
  expect(await ui.find({ text: '● LIVE' })).toBeTruthy()
})

test('dock: Hechos enseña todos sus agentes, sin «… y N más»', async ($, on) => {
  const many = Array.from({ length: 50 }, (_, i) => ({ id: `d${i}`, description: `Tarea ${i}`, type: 'general', status: 'completed' }))
  const { ui } = await mountDock($ as never, on as never, 56, undefined, many)
  expect(await ui.find({ type: 'Text', text: 'Hechos · 50' })).toBeTruthy()
  expect(await ui.findAll({ type: 'Text', text: /✓ T\d+/ })).toHaveLength(50)
  expect(await ui.find({ text: /✓ T1 / })).toBeTruthy()
  expect(await ui.find({ text: /✓ T50/ })).toBeTruthy()
  expect(await ui.find({ text: /más$/ })).toBeFalsy()
})

test('dock: bajo cada agente activo, su última herramienta; la ruta guarda su cola', async ($, on) => {
  // The engine's stand-ins go in before the first call on $.
  const o = on as any
  o('tool.call', { tool: 'Read' }, () => ({ result: { type: 'text', file: { filePath: '', content: '', numLines: 0, startLine: 1, totalLines: 0 } } }))
  o('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: '', stderr: '', interrupted: false } }))
  const { ui: before, clock, mount } = await mountDock($ as never, on as never, 56, undefined, AGENTS.slice(0, 1))
  expect(await before.find({ text: /arrancando…/ })).toBeTruthy()
  await ($ as any).tool.call({ tool: 'Read', file_path: '/srv/app/src/checkout/precio.ts', agentId: 'a1' })
  await clock.advance(1500)
  await before.unmount()
  let ui = await mount()
  expect((await ui.find({ type: 'Text', text: /^ +Read checkout\/precio\.ts$/ })).text).toBe('      Read checkout/precio.ts')
  expect(await ui.find({ text: /arrancando…/ })).toBeFalsy()
  await ($ as any).tool.call({ tool: 'Bash', command: 'git status', description: 'Estado del repo', agentId: 'a1' })
  await clock.advance(1500)
  await ui.unmount()
  ui = await mount()
  expect(await ui.find({ type: 'Text', text: '      Bash Estado del repo' })).toBeTruthy()
  // The main loop's calls go to the mission's line, never under an agent.
  await ($ as any).tool.call({ tool: 'Bash', command: 'ls', description: 'Listar', agentId: undefined })
  await clock.advance(1500)
  await ui.unmount()
  ui = await mount()
  expect(await ui.find({ type: 'Text', text: '      Bash Estado del repo' })).toBeTruthy()
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

test('elapsed lleva unidades y no pasa de 6 celdas por debajo de 100 h', () => {
  expect(elapsed(0)).toBe('0s')
  expect(elapsed(45_000)).toBe('45s')
  expect(elapsed(642_000)).toBe('10m42s')
  expect(elapsed(3_600_000)).toBe('1h00m')
  expect(elapsed(3_725_000)).toBe('1h02m')
  expect(elapsed(-5)).toBe('0s')
  for (const ms of [59_999, 3_599_999, 99 * 3_600_000 + 3_599_000]) expect(elapsed(ms).length).toBeLessThanOrEqual(6)
})

test('dock: una herramienta en marcha es actividad; el agente solo se atasca 2 min después de que acabe', async ($, on) => {
  const $$ = $ as any, o = on as any
  let finish: (v: unknown) => void = () => undefined
  o('tool.call', { tool: 'Bash' }, () => new Promise(resolve => { finish = resolve }))
  const first = await mountDock($ as never, on as never, 56, undefined, AGENTS.slice(0, 1))
  const call = $$.tool.call({ tool: 'Bash', command: 'make test', description: 'Correr los tests', agentId: 'a1' })
  // Five minutes inside one Bash: longer than any stall threshold, and still work.
  await first.clock.advance(300_000)
  await first.ui.unmount()
  let ui = await first.mount()
  expect(await ui.find({ type: 'Text', text: 'Trabajando · 1' })).toBeTruthy()
  expect(await ui.find({ text: /Bash Correr los tests/ })).toBeTruthy()
  expect(await ui.find({ text: /sin actividad/ })).toBeFalsy()
  finish({ result: { stdout: '', stderr: '', interrupted: false } })
  await call
  await first.clock.advance(123_000)
  await ui.unmount()
  ui = await first.mount()
  expect(await ui.find({ type: 'Text', text: 'Parados · 1' })).toBeTruthy()
  expect(await ui.find({ text: /2m0\ds sin actividad/ })).toBeTruthy()
})

test('dock: waiting e idle están parados por diseño: siguen en Trabajando con su motivo y no se atascan', async ($, on) => {
  const first = await mountDock($ as never, on as never, 56, undefined, [
    { id: 'w1', description: 'Aplicar el plan', type: 'general', status: 'waiting' },
    { id: 'i1', description: 'Revisor', type: 'teammate', status: 'idle' },
  ])
  await first.clock.advance(300_000)
  await first.ui.unmount()
  const ui = await first.mount()
  expect(await ui.find({ type: 'Text', text: 'Trabajando · 2' })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: 'Parados · 0' })).toBeTruthy()
  expect(await ui.find({ text: /en espera \(aprobación o tarea en segundo plano\)/ })).toBeTruthy()
  expect(await ui.find({ text: /en espera de un mensaje/ })).toBeTruthy()
  expect(await ui.find({ text: /sin actividad/ })).toBeFalsy()
})

// The dock reads the owner and the share of the cap from `handoff --estado`: one source, the CLI's.
const HOME = '/usr/u'
const out = (stdout: string, exitCode = 0) => ({ value: { exitCode, stdout, stderr: '' } }) as never
function estadoCli(on: never, estado: unknown, opts: { hangs?: boolean; exitCode?: number } = {}) {
  const o = on as any
  const runs: { argv: readonly string[]; init?: { timeoutMs?: number } }[] = []
  o('session.cwd', () => ({ value: '/w/p' }))
  o('session.id', () => ({ value: 'sesion-1' }))
  o('process.run', (_: unknown, e: { argv: readonly string[]; init?: { timeoutMs?: number } }) => {
    runs.push(e)
    const a = e.argv.join(' ')
    if (a === 'printenv HOME') return out(HOME)
    if (a.includes('--show-toplevel')) return out('/w/p\n')
    if (e.argv[0] === `${HOME}/.claude/bin/handoff`) return opts.hangs ? new Promise(() => undefined) : out(JSON.stringify(estado), opts.exitCode)
    return out('')
  })
  return runs
}
const ESTADO = { raiz: '/w/p', nucleo: '/w/p/.claude/estado/nucleo.md', bytes: 4030, tope: 6500, pct: 62 }

test('dock: muestra el % del tope y el dueño de esta sesión, leídos de handoff --estado', async ($, on) => {
  const runs = estadoCli(on as never, { ...ESTADO, dueno: { sesion: 'sesion-1', desde: '2026-10-19T10:00:00Z', vigente: true } })
  const { ui } = await mountDock($ as never, on as never, 56)
  expect(await ui.find({ type: 'Text', text: /nucleo 62% del tope/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /dueño: esta sesión/ })).toBeTruthy()
  const cli = runs.find(r => r.argv[0] === `${HOME}/.claude/bin/handoff`)
  expect(cli?.argv).toEqual([`${HOME}/.claude/bin/handoff`, '--estado', '--raiz', '/w/p'])
  expect(cli?.init?.timeoutMs).toBeLessThanOrEqual(3000)
})

test('dock: un dueño vigente de otra sesión se nombra', async ($, on) => {
  estadoCli(on as never, { ...ESTADO, dueno: { sesion: 'abcdef12-0000', desde: '2026-10-19T10:00:00Z', vigente: true } })
  const { ui } = await mountDock($ as never, on as never, 56)
  expect(await ui.find({ type: 'Text', text: /dueño: otra sesión \(abcdef12\)/ })).toBeTruthy()
})

test('dock: sin dueño, o con el dueño vencido, lo dice', async ($, on) => {
  estadoCli(on as never, { ...ESTADO, dueno: null })
  const { ui } = await mountDock($ as never, on as never, 56)
  expect(await ui.find({ type: 'Text', text: /dueño: ninguno/ })).toBeTruthy()
})

test('dock: sin proyecto (exit 3) o con el CLI caído no dibuja la fila de estado', async ($, on) => {
  estadoCli(on as never, { raiz: null }, { exitCode: 3 })
  const { ui } = await mountDock($ as never, on as never, 56)
  expect(await ui.find({ type: 'Text', text: /del tope/ })).toBeFalsy()
  expect(await ui.find({ type: 'Text', text: 'Hechos · 1' })).toBeTruthy()
})

test('dock: un CLI que no responde no bloquea el dibujo', async ($, on) => {
  estadoCli(on as never, ESTADO, { hangs: true })
  const { ui } = await mountDock($ as never, on as never, 56)
  expect(await ui.find({ type: 'Text', text: 'Hechos · 1' })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /del tope/ })).toBeFalsy()
})
