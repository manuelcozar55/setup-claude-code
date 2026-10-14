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
