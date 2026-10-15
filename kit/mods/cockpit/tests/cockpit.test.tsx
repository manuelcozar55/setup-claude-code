import { expect, mock, test } from 'claude-code/testing'

import { condense } from '../hooks/register'

const BAND = { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 110, scroll: { offset: 0, bodyRows: 20 }, view: {} }
const RUN = { args: '', origin: { kind: 'composer' as const }, presentation: { isFullscreen: true, columns: 160 } }
const DOCK = { title: 'Agent Dock', isFocused: true, bodyColumns: 56, placement: 'dock' as const, scroll: { offset: 0, bodyRows: 40 }, view: {} }

const TODOS = [
  { content: 'Leer la API', status: 'completed' as const, activeForm: 'Leyendo la API' },
  { content: 'Escribir el mod', status: 'in_progress' as const, activeForm: 'Escribiendo el mod' },
  { content: 'Probarlo', status: 'pending' as const, activeForm: 'Probándolo' },
]

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: la banda de contexto tiene handoff con confirmación`, async $ => {
    const ui = await $.ui.mount({ plugin: 'cockpit', surface, component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: /CONTEXTO/ })).toBeTruthy()
    expect(await ui.find({ key: 'ho-go' })).toBeFalsy()
    await ui.press({ key: 'handoff' })
    expect(await ui.find({ key: 'ho-go' })).toBeTruthy()
    expect(await ui.find({ key: 'ho-save' })).toBeTruthy()
    await ui.press({ key: 'handoff' })
    expect(await ui.find({ key: 'ho-go' })).toBeFalsy()
  })

  test(`${surface}: «no guardar + /clear» limpia sin escribir handoff y las etiquetas no llevan letra`, async ($, on) => {
    const clock = mock.clock(on)
    const writes: string[] = []
    const cleared: string[] = []
    on('fs.write', (_, e) => {
      writes.push(e.path)
      return { value: undefined }
    })
    on('command.run', (_, e) => {
      if (e.command === 'clear') cleared.push(e.command)
      return { text: '' }
    })
    const ui = await $.ui.mount({ plugin: 'cockpit', surface, component: 'AbovePrompt', props: BAND })
    await ui.press({ key: 'handoff' })
    for (const key of ['ho-go', 'ho-save', 'ho-no']) {
      expect((await ui.find({ key }))?.text).not.toMatch(/^[ygn] /)
    }
    expect((await ui.find({ key: 'ho-no' }))?.text).toBe('[no guardar + /clear]')
    await ui.press({ key: 'ho-no' })
    await clock.advance(400)
    expect(writes).toEqual([])
    expect(cleared).toEqual(['clear'])
    expect(await ui.find({ key: 'ho-no' })).toBeFalsy()
  })

  test(`${surface}: /simple muestra los pasos con su estado`, async ($, on) => {
    on('tool.call', { tool: 'TodoWrite' }, () => ({ result: { oldTodos: [], newTodos: TODOS } }) as never)
    await $.tool.call({ tool: 'TodoWrite', todos: TODOS })
    await $.command.run({ ...RUN, command: 'simple' })

    const ui = await $.ui.mount({ plugin: 'cockpit', surface, component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: /Paso 2 de 3/ })).toBeTruthy()
    expect(await ui.find({ text: 'Escribiendo el mod' })).toBeTruthy()
    expect(await ui.find({ text: 'Hecho' })).toBeTruthy()
    expect(await ui.find({ text: 'Siguiente' })).toBeTruthy()
  })

  test(`${surface}: el dock elige tamaño de equipo`, async $ => {
    const ui = await $.ui.mount({ plugin: 'cockpit', surface, component: 'Pane', requestId: 'cockpit', props: DOCK })
    expect(await ui.find({ text: /Auto: Claude decide/ })).toBeTruthy()
    await ui.press({ key: 'team-10' })
    expect(await ui.find({ text: /entre 10 ayudantes/ })).toBeTruthy()
  })
}

test('el tamaño de equipo y el modo simple viajan como contexto oculto del prompt', async ($, on) => {
  let seen: readonly string[] = []
  on('prompt.submit', (_, e) => {
    seen = e.context ?? []
    return { text: e.text }
  })
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: DOCK })
  await ui.press({ key: 'team-3' })
  await $.command.run({ ...RUN, command: 'simple' })
  await $.prompt.submit({ text: 'Revisa el checkout', wait: false, origin: { kind: 'composer' } })
  expect(seen.some(n => n.includes('tamaño de equipo 3'))).toBe(true)
  expect(seen.some(n => n.includes('modo simple'))).toBe(true)
})

test('condense quita markdown y corta en una frase', () => {
  expect(condense('## Hecho\n**Listo**: [doc](http://x) creado.')).toBe('Hecho Listo: doc creado.')
  const long = condense(`${'Primera frase bastante larga con contenido útil. '.repeat(4)}${'x'.repeat(300)}`)
  expect(long.length).toBeLessThanOrEqual(282)
  expect(long.endsWith('. …')).toBe(true)
})
