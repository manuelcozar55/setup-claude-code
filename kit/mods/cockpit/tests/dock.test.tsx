import { expect, mock, test } from 'claude-code/testing'

const DOCK = { title: 'Agent Dock', isFocused: true, bodyColumns: 56, placement: 'dock' as const, scroll: { offset: 0, bodyRows: 40 }, view: {} }
const DESC = 'Revisar el flujo de checkout completo'

for (const bodyColumns of [24, 28, 56]) {
  test(`el dock a ${bodyColumns} columnas no corta controles, resumen ni tarjetas`, async ($, on) => {
    const clock = mock.clock(on)
    on('agent.list', () => ({ value: [{ id: 'a1', description: DESC, type: 'general', status: 'running' }] }) as never)
    on('session.start', () => ({ cwd: '/tmp' }))
    on('command.register', () => ({ value: undefined }) as never)
    on('ui.open', () => ({ value: { isPlaced: true } }) as never)
    await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
    await clock.advance(1500)
    const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: { ...DOCK, bodyColumns } })
    expect(await ui.find({ text: 'Agent Dock' })).toBeTruthy()
    expect(await ui.find({ text: /E\s?Q\s?U\s?I\s?P\s?O|A G E N T/ })).toBeFalsy()
    for (const key of ['team-1', 'team-3', 'team-10', 'team-0']) expect(await ui.find({ key })).toBeTruthy()
    expect(await ui.find({ text: /●.*○.*✓.*×/ })).toBeTruthy()
    expect(await ui.find({ text: DESC })).toBeTruthy()
  })
}

const AGENTS = [
  { id: 'a1', description: 'Revisar el flujo de checkout completo', type: 'general', status: 'running', activity: 'Bash: make test', tools: 12 },
  { id: 'a2', description: 'Contar ficheros', type: 'general', status: 'completed', tools: 3 },
]

async function mountDock($: never, on: never, bodyColumns: number, mission?: string) {
  const $$ = $ as any, o = on as any
  const clock = mock.clock(o)
  o('agent.list', () => ({ value: AGENTS }))
  o('session.start', () => ({ cwd: '/tmp' }))
  o('command.register', () => ({ value: undefined }))
  o('ui.open', () => ({ value: { isPlaced: true } }))
  o('prompt.submit', (_: unknown, e: { text: string }) => ({ text: e.text }))
  await $$.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  if (mission) await $$.prompt.submit({ text: mission, wait: false, origin: { kind: 'composer' } })
  await clock.advance(1500)
  return $$.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: { ...DOCK, bodyColumns } })
}

// The first dock shipped green on prop checks while the real terminal wrapped: measure the drawn text instead.
for (const bodyColumns of [24, 30, 44, 56, 66]) {
  test(`dock a ${bodyColumns}: barra y contador en una línea que cabe, actividad visible, contadores sin envolver`, async ($, on) => {
    const ui = await mountDock($ as never, on as never, bodyColumns)
    const cols = Math.max(24, bodyColumns)
    const card = await ui.find({ key: 'a1' })
    const inner = (card.props.width as number) - 2
    const row = await ui.find({ type: 'Text', text: /[━─]+\s+\d+h$/ })
    expect(row.text.length).toBeLessThanOrEqual(inner)
    expect(row.text).toMatch(/^[━─]{4,} +\d+h$/)
    expect(await ui.find({ text: /● arrancando…/ })).toBeTruthy()
    const counts = await ui.find({ type: 'Text', text: /●.*○.*✓.*×/ })
    expect(counts.text.length).toBeLessThanOrEqual(cols)
    expect(counts.text).not.toContain('\n')
  })
}

test('dock: dos columnas cuando caben', async ($, on) => {
  const ui = await mountDock($ as never, on as never, 62)
  expect((await ui.find({ key: 'a1' })).props.width).toBe(30)
})

test('dock: una columna en estrecho', async ($, on) => {
  const ui = await mountDock($ as never, on as never, 44)
  expect((await ui.find({ key: 'a1' })).props.width).toBe(44)
})

test('dock: la misión nace plegada en una línea y un clic la despliega y la pliega', async ($, on) => {
  const LONG = 'Revisar a fondo el flujo de checkout, precios y red con tres subagentes en paralelo'
  const ui = await mountDock($ as never, on as never, 30, LONG)
  const folded = await ui.find({ type: 'Text', text: /^▸ Revisar/ })
  expect(folded.text.length).toBeLessThanOrEqual(30)
  expect(folded.text.endsWith('…')).toBe(true)
  expect(await ui.find({ text: LONG })).toBeFalsy()
  await ui.press({ key: 'mission' })
  expect(await ui.find({ type: 'Text', text: `▾ ${LONG}` })).toBeTruthy()
  await ui.press({ key: 'mission' })
  expect(await ui.find({ text: LONG })).toBeFalsy()
})

test('dock: una notificación de tarea no pisa la misión de la persona', async ($, on) => {
  const ui = await mountDock($ as never, on as never, 56, 'Revisar el checkout')
  await ($ as any).prompt.submit({ text: '<task-notification>done</task-notification>', wait: false, origin: { kind: 'task-notification' } })
  expect(await ui.find({ text: /task-notification/ })).toBeFalsy()
  expect(await ui.find({ text: /Revisar el checkout/ })).toBeTruthy()
})
