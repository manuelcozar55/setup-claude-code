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
    expect(await ui.find({ text: /atascados/ })).toBeTruthy()
    expect(await ui.find({ text: /en cola/ })).toBeTruthy()
    expect(await ui.find({ text: DESC })).toBeTruthy()
  })
}

test('dock: dos columnas, contadores en una línea y misión expandible con un clic', async ($, on) => {
  const clock = mock.clock(on)
  const LONG = 'Revisar a fondo el flujo de checkout, precios y red con tres subagentes en paralelo'
  on('agent.list', () => ({ value: ['a1', 'a2', 'a3'].map(id => ({ id, description: `Tarea ${id}`, type: 'general', status: 'running' })) }) as never)
  on('session.start', () => ({ cwd: '/tmp' }))
  on('command.register', () => ({ value: undefined }) as never)
  on('ui.open', () => ({ value: { isPlaced: true } }) as never)
  on('prompt.submit', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  await $.prompt.submit({ text: LONG, wait: false, origin: { kind: 'composer' } })
  await clock.advance(1500)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: { ...DOCK, bodyColumns: 62 } })
  const card = await ui.find({ key: 'a1' })
  expect(card?.props?.width).toBe(30)
  const counts = await ui.find({ type: 'Text', text: /trabajando.*en cola.*hechos.*atascados/ })
  expect(counts?.props?.wrap).toBe('truncate-end')
  const before = await ui.find({ type: 'Text', text: /▸ Revisar a fondo/ })
  expect(before?.props?.wrap).toBe('truncate-end')
  await ui.press({ key: 'mission' })
  const after = await ui.find({ type: 'Text', text: /▾ Revisar a fondo/ })
  expect(after?.props?.wrap).toBe('wrap')
})
