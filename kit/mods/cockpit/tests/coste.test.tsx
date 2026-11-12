import { expect, mock, test, type TestBody } from 'claude-code/testing'

// W3: lo que cuesta tokens sin que la persona lo pida (autosave y handoff automático), y cuándo el mod calla del todo
// (sesión no interactiva, Claude Code demasiado viejo). Escenarios T2/T5/T6 de la auditoría D, con su aserción.
const RUN = { args: '', origin: { kind: 'composer' as const }, presentation: { isFullscreen: true, columns: 160 } }
const HOME = '/usr/u'
const BIN = `${HOME}/.claude/bin/handoff`
const EST = '/work/proyecto/.claude/estado'
const DIRTY = `${EST}/autosave.dirty`
const LOG = `${HOME}/.claude/session-logs/autosave-cockpit.log`
const TMP = '/tmp/cockpit-handoff.Ab12Cd'
const PREV = '# Estado\n\n## Objetivo\nhaz X\n\n## Invariantes\n- no tocar Y\n## Plan\n- [ ] T1\n'
const PLAN = '## Plan\n- [ ] T2\n## Siguiente acción\nT2\n'
const DONE_TURN = { answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' as const }
const MIN = 60_000
const BAND = { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 200, scroll: { offset: 0, bodyRows: 20 }, view: {} }
const USAGE = { input_tokens: 100, output_tokens: 50, cache_read_input_tokens: 20, cache_creation_input_tokens: 5 }

const ok = (stdout = '') => ({ value: { exitCode: 0, stdout, stderr: '' } }) as never

type Opts = {
  dirty?: string
  tokens?: number
  fork?: 'ok' | 'nothing' | 'error' | 'empty'
  cli?: number
  owner?: { sesion: string; vigente: boolean } | null
  env?: string
  autosaveEnv?: string
  draft?: string
  noOn?: boolean
  version?: string | 'throws'
}

async function setup($: any, on: Parameters<TestBody>[1], o: Opts = {}) {
  const files: Record<string, string> = { [BIN]: '#!/usr/bin/env bash\n', [`${EST}/nucleo.md`]: PREV }
  if (o.dirty !== undefined) files[DIRTY] = o.dirty
  const seen = { calls: 0, forks: 0, prompts: [] as string[], toasts: [] as string[], logs: [] as string[], opens: 0, clears: 0, fills: [] as string[], tokens: o.tokens ?? 50_000, sid: 'sesion-1' }
  on('session.start', () => ({ cwd: '/work/proyecto' }))
  on('command.register', () => ({ value: undefined }) as never)
  on('ui.open', () => { seen.opens++; return { value: undefined } as never })
  on('session.cwd', () => ({ value: '/work/proyecto/sub' }))
  on('session.root', () => ({ value: '/work/proyecto/sub' }))
  on('session.id', () => ({ value: seen.sid }) as never)
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('session.version', () => {
    if (o.version === 'throws') throw new Error('sin session.version')
    const v = o.version ?? '2.1.311'
    return { value: { version: v, base: v } } as never
  })
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      rateLimits: [],
      context: { tokens: seen.tokens, window: 1_000_000, breakdown: { totalTokens: seen.tokens, rawMaxTokens: 200_000, categories: [{ kind: 'buffer', name: 'Autocompact buffer', tokens: 20_000 }] } },
    },
  }) as never)
  on('agent.list', () => ({ value: [] }) as never)
  on('process.run', (_, e) => {
    const a = e.argv.join(' ')
    if (a === 'printenv HOME') return ok(HOME)
    if (a === 'printenv CLAUDE_HOME') return ok('')
    if (a === 'printenv COCKPIT_AUTO_HANDOFF') return ok(o.env ?? 'off')
    if (a === 'printenv COCKPIT_AUTOSAVE') return o.autosaveEnv ? ok(o.autosaveEnv) : ({ value: { exitCode: 1, stdout: '', stderr: '' } }) as never
    if (a.includes('--show-toplevel')) return ok('/work/proyecto\n')
    if (e.argv[0] === 'find') return ok('')
    if (e.argv[0] === 'mktemp') return ok(`${TMP}\n`)
    if (e.argv[0] === 'rm') return ok()
    if (e.argv[0] === BIN && e.argv[1] === '--estado') return ok(JSON.stringify({ nucleo: `${EST}/nucleo.md`, pct: 1, bytes: 10, tope: 5700, dueno: o.owner ?? null, agentes_vivos: 0 }))
    if (e.argv[0] === BIN) {
      seen.calls++
      if (o.cli) return { value: { exitCode: o.cli, stdout: '', stderr: 'dueño ajeno' } } as never
      files[`${EST}/nucleo.md`] = files[TMP] ?? ''
      delete files[DIRTY]
      return ok(JSON.stringify({ nucleo: `${EST}/nucleo.md`, sha256: 'a'.repeat(64) }))
    }
    return ok()
  })
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }) as never)
  on('fs.write', (_, e) => {
    files[e.path] = e.text
    return { value: undefined }
  })
  on('model.fork', (_, e) => {
    seen.forks++
    seen.prompts.push(e.prompt)
    if (o.fork === 'nothing') return { value: { isAnswered: false, reason: 'nothing-to-fork' } } as never
    if (o.fork === 'empty') return { value: { isAnswered: false, reason: 'empty-reply', usage: USAGE } } as never
    if (o.fork === 'error') return { value: { isAnswered: false, reason: 'api-error', status: 529, usage: USAGE } } as never
    return { value: { isAnswered: true, text: PLAN, usage: USAGE } } as never
  })
  on('command.run', (_, e) => {
    if (e.command === 'clear') seen.clears++
    return { text: '' }
  })
  on('prompt.read', () => ({ value: { text: o.draft ?? '', cursor: 0 } }))
  on('prompt.fill', (_, e) => {
    seen.fills.push(e.text)
    return { isFilled: true } as never
  })
  on('turn.complete', (_, e) => ({ text: e.answer }) as never)
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('ui.toast', (_, e) => {
    seen.toasts.push(e.text)
    return { value: undefined } as never
  })
  on('ui.log', (_, e) => {
    seen.logs.push(e.text)
    return { value: undefined } as never
  })
  // The module keeps its state between tests: a /clear starts it from zero.
  await $.session.end({ reason: 'clear', sessionId: 's0', resume: { id: 's0' } })
  if (!o.noOn) await $.command.run({ ...RUN, command: 'autosave', args: 'on' })
  return { files, seen }
}

const start = ($: any, isInteractive = true) => $.session.start({ cwd: '/work/proyecto', surface: isInteractive ? 'terminal' : null, isInteractive })

// 40 min of work (a turn every 4 min, dirty again after each) and then 80 min with no turns, the timer alone.
async function threeHours($: any, clock: ReturnType<typeof mock.clock>, files: Record<string, string>) {
  for (let i = 0; i < 10; i++) {
    await clock.advance(4 * MIN - 50)
    files[DIRTY] = 'motivo=edit\n'
    await $.turn.complete(DONE_TURN)
    await clock.advance(50)
  }
  for (let i = 0; i < 8; i++) {
    files[DIRTY] = 'motivo=edit\n'
    await clock.advance(10 * MIN + 7_000)
  }
}

test('B1: si el dueño del estado es otra sesión vigente no hay fork, y a la tercera se para con un solo aviso', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n', owner: { sesion: 'otra-sesion-id', vigente: true } })
  await start($)
  await threeHours($, clock, files)
  expect(seen.forks).toBe(0)
  expect(seen.calls).toBe(0)
  expect(seen.toasts).toHaveLength(1)
  expect(seen.toasts[0]).toContain('/autosave on')
  expect(seen.toasts[0]).toContain('otra sesión')
})

for (const [name, opt] of [
  ['el CLI rechaza con rc 5 (carrera: el dueño aparece después del --estado)', { cli: 5 }],
  ['el CLI rechaza con rc 2', { cli: 2 }],
  ['la API falla en el fork', { fork: 'error' as const }],
] as const) {
  test(`B1: ${name}: como mucho 3 intentos y un solo aviso visible`, async ($, on) => {
    const clock = mock.clock(on)
    const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n', ...opt })
    await start($)
    await threeHours($, clock, files)
    expect(seen.forks).toBeLessThanOrEqual(3)
    expect(seen.toasts).toHaveLength(1)
    expect(seen.toasts[0]).toContain('autosave')
    expect(seen.toasts[0]).toContain('/autosave on')
    expect((await $.command.run({ ...RUN, command: 'autosave', args: 'status' })).text).toContain('Autosave off')
  })
}

test('B1: tras un fallo el reintento espera 10 min y tras el segundo 20 (retroceso exponencial)', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n', fork: 'error' })
  await start($)
  await $.turn.complete(DONE_TURN)
  const at: number[] = []
  for (let m = 1; m <= 120; m++) {
    files[DIRTY] = 'motivo=edit\n'
    const before = seen.forks
    await clock.advance(MIN)
    if (seen.forks > before) at.push(m)
  }
  expect(at).toHaveLength(3)
  expect((at[1] ?? 0) - (at[0] ?? 0)).toBeGreaterThanOrEqual(10)
  expect((at[2] ?? 0) - (at[1] ?? 0)).toBeGreaterThanOrEqual(20)
})

test('B1: un éxito reinicia la cuenta de fallos', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n', fork: 'ok' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
  expect(seen.toasts).toEqual([])
})

test('B1: el log del autosave lleva el usage del fork (entrada, salida, caché leída y escrita)', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=compact\n' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
  const line = (files[LOG] ?? '').trim().split('\t')
  expect(line).toHaveLength(10)
  expect(line.slice(6)).toEqual(['100', '50', '20', '5'])
})

test('B1: un fork fallido también queda en el log con su usage', async ($, on) => {
  const clock = mock.clock(on)
  const { files } = await setup($, on, { dirty: 'motivo=compact\n', fork: 'error' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  const line = (files[LOG] ?? '').trim().split('\t')
  expect(line[2]).toContain('fallo')
  expect(line.slice(6)).toEqual(['100', '50', '20', '5'])
})

test('B1: el autosave con modelo es opt-in: sin /autosave on ni COCKPIT_AUTOSAVE=on no forkea', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=compact\n', noOn: true })
  await start($)
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(30 * MIN)
  files[DIRTY] = 'motivo=compact\n'
  await clock.advance(30 * MIN)
  expect(seen.forks).toBe(0)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect((await ui.find({ text: /AUTOSAVE/ }))?.text).toMatch(/off/)
  expect((await $.command.run({ ...RUN, command: 'autosave', args: 'status' })).text).toContain('Autosave off')
})

test('B1: COCKPIT_AUTOSAVE=on lo activa al arrancar y la banda lo muestra', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n', noOn: true, autosaveEnv: 'on' })
  await start($)
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect((await ui.find({ text: /AUTOSAVE/ }))?.text).toMatch(/on/)
})

// T5: -p y SDK cargan el plugin y no hay nadie delante.
for (const [name, opt] of [['ok', {}], ['cli rc 2', { cli: 2 }], ['fork api-error', { fork: 'error' as const }]] as const) {
  test(`T5: con isInteractive false no hay temporizadores, dock, handoff automático ni autosave (${name})`, async ($, on) => {
    const clock = mock.clock(on)
    const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n', env: '70', tokens: 150_000, ...opt })
    await start($, false)
    await $.turn.complete(DONE_TURN)
    for (let i = 0; i < 12; i++) {
      files[DIRTY] = 'motivo=edit\n'
      await clock.advance(10 * MIN)
      await $.turn.complete(DONE_TURN)
    }
    expect(seen.forks).toBe(0)
    expect(seen.calls).toBe(0)
    expect(seen.opens).toBe(0)
    expect(seen.toasts).toEqual([])
  })
}

// T2: el /clear no se hace (texto en el prompt) y el contexto sigue por encima del 70 %.
test('T2: el handoff automático guarda una vez por cruce del umbral, no en cada turno', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { tokens: 150_000, env: '70', draft: 'lo siguiente que pienso pedir', noOn: true })
  for (let i = 0; i < 5; i++) {
    await clock.advance(2 * MIN)
    await $.turn.complete(DONE_TURN)
    await clock.advance(1000)
  }
  expect(seen.forks).toBe(1)
  expect(seen.toasts.filter(t => t.includes('handoff automático'))).toHaveLength(1)
})

test('T2: al bajar del umbral (compactación) el cruce siguiente vuelve a guardar', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { tokens: 150_000, env: '70', draft: 'texto', noOn: true })
  for (let i = 0; i < 2; i++) {
    await clock.advance(2 * MIN)
    await $.turn.complete(DONE_TURN)
    await clock.advance(1000)
  }
  expect(seen.forks).toBe(1)
  seen.tokens = 20_000
  await clock.advance(2 * MIN)
  await $.turn.complete(DONE_TURN)
  await clock.advance(1000)
  seen.tokens = 150_000
  await clock.advance(2 * MIN)
  await $.turn.complete(DONE_TURN)
  await clock.advance(1000)
  expect(seen.forks).toBe(2)
})

test('«Contexto limpio» solo si el id de sesión cambió tras el /clear', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { noOn: true })
  await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  expect(seen.clears).toBe(1)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  const msg = (await ui.find({ text: /^[✓✗] / }))?.text ?? ''
  expect(msg).not.toContain('Contexto limpio')
  expect(msg).toContain('no cambió')
})


// La versión mínima: por debajo el mod se apaga con un aviso; sin session.version se sigue (la API no obliga a tenerlo).
test('versión mínima: con Claude Code anterior a 2.1.311 el mod se apaga con un aviso y no abre dock ni temporizadores', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=compact\n', version: '2.1.300' })
  await start($)
  await $.turn.complete(DONE_TURN)
  for (let i = 0; i < 3; i++) {
    files[DIRTY] = 'motivo=compact\n'
    await clock.advance(10 * MIN)
  }
  expect(seen.opens).toBe(0)
  expect(seen.forks).toBe(0)
  expect(seen.toasts).toHaveLength(1)
  expect(seen.toasts[0]).toContain('2.1.311')
  expect(seen.toasts[0]).toContain('2.1.300')
})

test('versión mínima: 2.1.311 o posterior funciona (dock abierto)', async ($, on) => {
  mock.clock(on)
  const { seen } = await setup($, on, { version: '2.2.0' })
  await start($)
  expect(seen.opens).toBe(1)
  expect(seen.toasts).toEqual([])
})

test('versión mínima: si session.version no existe el mod sigue y lo deja en el log de debug', async ($, on) => {
  mock.clock(on)
  const { seen } = await setup($, on, { version: 'throws' })
  await start($)
  expect(seen.opens).toBe(1)
  expect(seen.logs.some(l => l.includes('versión'))).toBe(true)
})

// Fallos visibles para quien no es el autor: cada uno dice qué pasó y qué hacer después.
async function bandMsg($: any) {
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  return (await ui.find({ text: /^[✓✗] / }))?.text ?? ''
}

test('fallo visible: el fork con error de API dice que no se guardó nada y qué repetir', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { noOn: true, fork: 'error' })
  await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  const msg = await bandMsg($)
  expect(msg).toContain('HTTP 529')
  expect(msg).toContain('no se guardó nada')
  expect(msg).toContain('repite /handoff')
  expect(seen.clears).toBe(0)
})

test('fallo visible: el fork que vuelve vacío dice que el modelo no devolvió texto', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { noOn: true, fork: 'empty' })
  await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  expect(await bandMsg($)).toContain('no devolvió texto')
  expect(seen.clears).toBe(0)
})

test('fallo visible: sin el comando handoff el mensaje dice cómo instalarlo y no forkea', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { noOn: true })
  delete files[BIN]
  await $.command.run({ ...RUN, command: 'handoff', args: '' })
  await clock.advance(400)
  expect(await bandMsg($)).toContain('install.sh --apply')
  expect(seen.forks).toBe(0)
})

test('fallo visible: /autosave status sin .claude/estado/ manda a handoff --iniciar', async ($, on) => {
  const { files } = await setup($, on, { noOn: true })
  delete files[`${EST}/nucleo.md`]
  const res = (await $.command.run({ ...RUN, command: 'autosave', args: 'status' })) as { text?: string }
  expect(res.text ?? '').toContain('handoff --iniciar')
})
