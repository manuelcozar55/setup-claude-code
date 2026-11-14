import { expect, mock, test, type TestBody } from 'claude-code/testing'

// ADR 028, layer 2: the silent synthesis. The files live in a map; the CLI is a stub that follows the handoff contract.
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
const DOCK = { title: 'Agent Dock', isFocused: true, bodyColumns: 56, placement: 'dock' as const, scroll: { offset: 0, bodyRows: 40 }, view: {} }

const ok = (stdout = '') => ({ value: { exitCode: 0, stdout, stderr: '' } }) as never
const no = () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }) as never

async function setup(
  $: any,
  on: Parameters<TestBody>[1],
  o: { linked?: boolean; dirty?: string; tokens?: number; files?: Record<string, string>; fork?: 'ok' | 'nothing' | 'error'; cli?: number; live?: boolean; env?: string; hold?: Promise<void> } = {},
) {
  const files: Record<string, string> = { [BIN]: '#!/usr/bin/env bash\n', [`${EST}/nucleo.md`]: PREV, ...o.files }
  if (o.dirty !== undefined) files[DIRTY] = o.dirty
  const seen = { argvs: [] as (readonly string[])[], calls: 0, forks: 0, prompts: [] as string[], toasts: [] as string[], logs: [] as string[], fills: [] as string[], cli: 0, tokens: o.tokens ?? 50_000 }
  on('session.cwd', () => ({ value: '/work/proyecto/sub' }))
  on('session.root', () => ({ value: o.linked ? HOME : '/work/proyecto/sub' }))
  on('session.id', () => ({ value: 'sesion-1' }) as never)
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      rateLimits: [],
      context: { tokens: seen.tokens, window: 1_000_000, breakdown: { totalTokens: seen.tokens, rawMaxTokens: 200_000, categories: [{ kind: 'buffer', name: 'Autocompact buffer', tokens: 20_000 }] } },
    },
  }) as never)
  on('agent.list', () => ({ value: o.live === false ? [] : [{ id: 'a1', status: 'running', description: '', type: 'x' }] }) as never)
  on('process.run', (_, e) => {
    seen.argvs.push(e.argv)
    const a = e.argv.join(' ')
    if (a === 'printenv HOME') return ok(HOME)
    if (a === 'printenv CLAUDE_HOME') return ok('')
    if (a === 'printenv COCKPIT_AUTO_HANDOFF') return ok(o.env ?? 'off')
    if (a.includes('--show-toplevel')) return o.linked ? no() : ok('/work/proyecto\n')
    if (e.argv[0] === 'find') return ok('')
    if (e.argv[0] === 'mktemp') return ok(`${TMP}\n`)
    if (e.argv[0] === 'rm') return ok()
    if (e.argv[0] === BIN && e.argv[1] === '--estado') return ok(JSON.stringify({ nucleo: `${EST}/nucleo.md`, pct: 1, bytes: 10, tope: 5700, dueno: null, agentes_vivos: o.live === false ? 0 : 1, ...(o.linked ? { raiz: '/work/proyecto', sesion: `${HOME}/.claude/estado/sesiones/20261114-1000-42`, vinculado: true } : {}) }))
    if (e.argv[0] === BIN) {
      seen.calls++
      if (o.cli) return { value: { exitCode: o.cli, stdout: '', stderr: 'dueño ajeno' } } as never
      seen.cli++
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
  on('model.fork', async (_, e) => {
    await o.hold
    seen.forks++
    seen.prompts.push(e.prompt)
    if (o.fork === 'nothing') return { value: { isAnswered: false, reason: 'nothing-to-fork' } } as never
    if (o.fork === 'error') return { value: { isAnswered: false, reason: 'api-error' } } as never
    return { value: { isAnswered: true, text: PLAN, usage: {} } } as never
  })
  on('command.run', () => ({ text: '' }))
  on('prompt.read', () => ({ value: { text: '', cursor: 0 } }))
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
  // The module keeps its counters between tests: a /clear and /autosave on start each one from zero.
  await $.session.end({ reason: 'clear', sessionId: 's0', resume: { id: 's0' } })
  await $.command.run({ ...RUN, command: 'autosave', args: 'on' })
  return { files, seen }
}

// n answered turns, `minutes` apart in total, letting the work scheduled behind each turn end run.
async function turns($: any, clock: ReturnType<typeof mock.clock>, n: number, minutes = 0) {
  for (let i = 0; i < n; i++) {
    if (i === 1 && minutes) await clock.advance(minutes * MIN)
    await $.turn.complete(DONE_TURN)
    await clock.advance(50)
  }
}

test('autosave: con dirty, ≥5 turnos y ≥10 min por turnos (8) guarda en silencio: sin toast, banda, recibo ni relleno', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\ndesde=2026-11-09T10:00:00Z\nultimo=2026-11-09T10:05:00Z\n' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await turns($, clock, 6)
  expect(seen.forks).toBe(0)
  await turns($, clock, 1)
  expect(seen.forks).toBe(1)
  expect(seen.cli).toBe(1)
  expect(files[`${EST}/nucleo.md`]).toContain('T2')
  expect(seen.toasts).toEqual([])
  expect(seen.fills).toEqual([])
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 200, scroll: { offset: 0, bodyRows: 20 }, view: {} } })
  expect(await ui.find({ text: /Guardado en|Handoff:|guardado \d/ })).toBeFalsy()
  const pane = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'Pane', requestId: 'cockpit', props: DOCK })
  expect(await pane.find({ text: /^guardado \d\d:\d\d$/ })).toBeTruthy()
  const line = (files[LOG] ?? '').trim().split('\t')
  expect(line).toHaveLength(10)
  expect(line[1]).toBe('sesion-1')
  expect(line[2]).toBe('turn')
  expect(Number(line[3])).toBeGreaterThan(1000)
  expect(Number(line[4])).toBe(new TextEncoder().encode(PLAN).length)
  expect(line[0]).toMatch(/^\d{4}-\d\d-\d\dT/)
  expect(await $.command.run({ ...RUN, command: 'autosave', args: 'status' })).toEqual({ text: expect.stringMatching(/Autosave on\. Última síntesis: \d\d:\d\d \(1 en la sesión\)/) })
})

test('autosave: sesión de ~ vinculada a un proyecto: lee el dirty y guarda en el proyecto que devuelve el CLI, sin --raiz', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { linked: true, dirty: 'motivo=compact\ndesde=2026-11-09T10:00:00Z\nultimo=2026-11-09T10:05:00Z\n' })
  await turns($, clock, 1, 0)
  await clock.advance(2 * MIN)
  await turns($, clock, 1)
  expect(seen.forks).toBe(1)
  expect(files[`${EST}/nucleo.md`]).toContain('T2')
  expect(seen.argvs.filter(a => a[0] === BIN).every(a => !a.includes('--raiz'))).toBe(true)
})

test('autosave: sin dirty no guarda nunca',async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on)
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await turns($, clock, 10)
  expect(seen.forks).toBe(0)
})

test('autosave: topes: ni 8 turnos sin 10 min ni 10 min con menos de 5 turnos', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=edit\n' })
  await turns($, clock, 10)
  expect(seen.forks).toBe(0)
  await clock.advance(11 * MIN)
  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } })
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await turns($, clock, 3)
  expect(seen.forks).toBe(0)
})

test('autosave: +15 puntos de contexto desde la última síntesis dispara «turn»', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n', tokens: 30_000 })
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await turns($, clock, 4)
  expect(seen.forks).toBe(0)
  seen.tokens = 80_000
  await turns($, clock, 1)
  expect(seen.forks).toBe(1)
  expect(files[LOG]).toContain('\tturn\t')
})

test('autosave: un commit visto en tool.call dispara «goal» con dirty y no sin él', async ($, on) => {
  const clock = mock.clock(on)
  on('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: '', stderr: '', interrupted: false } }) as never)
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await $.tool.call({ tool: 'Bash', command: 'git commit -m x', description: 'commit' })
  await turns($, clock, 3)
  expect(seen.forks).toBe(0)
  await turns($, clock, 1)
  expect(seen.forks).toBe(1)
  expect(files[LOG]).toContain('\tgoal\t')
  // Saved: the goal is spent, and with no dirty mark a new commit saves nothing.
  await clock.advance(11 * MIN)
  await $.tool.call({ tool: 'Bash', command: 'gh pr create', description: 'pr' })
  await turns($, clock, 6)
  expect(seen.forks).toBe(1)
})

test('autosave: TodoWrite con todos completados dispara «goal»', async ($, on) => {
  const clock = mock.clock(on)
  const todos = [{ content: 'a', status: 'completed' as const, activeForm: 'a' }]
  on('tool.call', { tool: 'TodoWrite' }, () => ({ result: { oldTodos: [], newTodos: todos } }) as never)
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await $.tool.call({ tool: 'TodoWrite', todos })
  await turns($, clock, 5)
  expect(seen.forks).toBe(1)
  expect(files[LOG]).toContain('\tgoal\t')
})

test('autosave: verificaciones.log que pasa de rc≠0 a rc 0 dispara «goal»; el baseline viejo no', async ($, on) => {
  const clock = mock.clock(on)
  const VER = `${EST}/verificaciones.log`
  const { files, seen } = await setup($, on, { dirty: 'motivo=edit\n', files: { [VER]: '2026-11-09T10:00:00Z\t1\tmake test\n2026-11-09T10:05:00Z\t0\tmake test\n' } })
  await $.turn.complete(DONE_TURN)
  await clock.advance(11 * MIN)
  await turns($, clock, 5)
  expect(seen.forks).toBe(0)
  files[VER] += '2026-11-09T10:20:00Z\t1\tmake test\n2026-11-09T10:25:00Z\t0\tmake test\n'
  await turns($, clock, 1)
  expect(seen.forks).toBe(1)
  expect(files[LOG]).toContain('\tgoal\t')
})

test('autosave: tras una compactación (motivo=compact) guarda con ≥1 min, sin esperar 5 turnos', async ($, on) => {
  const clock = mock.clock(on)
  const { files, seen } = await setup($, on, { dirty: 'motivo=compact\n' })
  await $.turn.complete(DONE_TURN)
  expect(seen.forks).toBe(0)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
  expect(files[LOG]).toContain('\tproactive\t')
  expect(seen.toasts).toEqual([])
})

test('autosave: agentes vivos no impiden guardar; un turno de subagente no cuenta', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete({ ...DONE_TURN, agentId: 'a1' })
  await clock.advance(50)
  expect(seen.forks).toBe(0)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
})

test('autosave: nothing-to-fork se calla (sin banda ni PING) y se reintenta en el siguiente turno', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n', fork: 'nothing' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(2)
  expect(seen.fills).toEqual([])
  expect(seen.toasts).toEqual([])
})

test('autosave: un fallo va a ui.log, no a la banda, y espera 10 min antes de reintentar', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n', fork: 'error' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
  expect(seen.logs.some(l => l.includes('autosave fallido'))).toBe(true)
  expect(seen.toasts).toEqual([])
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 200, scroll: { offset: 0, bodyRows: 20 }, view: {} } })
  expect(await ui.find({ text: /Handoff fallido/ })).toBeFalsy()
  await clock.advance(11 * MIN)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(2)
})

test('autosave: la red temporal (cada 10 min) guarda si hay dirty y no hay turno en marcha', async ($, on) => {
  const clock = mock.clock(on)
  on('session.start', () => ({ cwd: '/work/proyecto' }))
  on('command.register', () => ({ value: undefined }) as never)
  on('ui.open', () => ({ value: undefined }) as never)
  const { seen } = await setup($, on, { dirty: 'motivo=edit\n' })
  await $.turn.complete(DONE_TURN)
  await $.session.start({ cwd: '/work/proyecto', surface: 'terminal', isInteractive: true })
  await clock.advance(9 * MIN)
  expect(seen.forks).toBe(0)
  await clock.advance(2 * MIN)
  expect(seen.forks).toBe(1)
})

test('/autosave off desactiva, status informa y on reactiva', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n' })
  const off = await $.command.run({ ...RUN, command: 'autosave', args: 'off' })
  expect(off.text).toContain('Autosave off.')
  expect(off.text).toContain('Marca dirty: compact.')
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(0)
  const status = await $.command.run({ ...RUN, command: 'autosave', args: 'status' })
  expect(status.text).toContain('Autosave off.')
  expect(status.text).toContain('Última síntesis: ninguna (0 en la sesión)')
  expect((await $.command.run({ ...RUN, command: 'autosave', args: 'on' })).text).toContain('Autosave on.')
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(1)
})

const BAND = { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 200, scroll: { offset: 0, bodyRows: 20 }, view: {} }
async function startTimer($: any, on: Parameters<TestBody>[1]) {
  on('session.start', () => ({ cwd: '/work/proyecto' }))
  on('command.register', () => ({ value: undefined }) as never)
  on('ui.open', () => ({ value: undefined }) as never)
}

test('autosave: /autosave off corta también la red temporal', async ($, on) => {
  const clock = mock.clock(on)
  await startTimer($, on)
  const { seen } = await setup($, on, { dirty: 'motivo=edit\n' })
  await $.turn.complete(DONE_TURN)
  await $.session.start({ cwd: '/work/proyecto', surface: 'terminal', isInteractive: true })
  await $.command.run({ ...RUN, command: 'autosave', args: 'off' })
  await clock.advance(25 * MIN)
  expect(seen.forks).toBe(0)
})

test('autosave: la red temporal no dispara con un turno en marcha ni tras un /clear', async ($, on) => {
  const clock = mock.clock(on)
  await startTimer($, on)
  const { seen } = await setup($, on, { dirty: 'motivo=edit\n' })
  await $.turn.complete(DONE_TURN)
  await $.session.start({ cwd: '/work/proyecto', surface: 'terminal', isInteractive: true })
  await $.turn.start({ text: 'otra cosa', turnId: 't2' })
  await clock.advance(11 * MIN)
  expect(seen.forks).toBe(0)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } })
  await clock.advance(25 * MIN)
  expect(seen.forks).toBe(0)
})

for (const code of [4, 5]) {
  test(`autosave: el CLI con rc ${code} en silencio no deja toast ni banda`, async ($, on) => {
    const clock = mock.clock(on)
    const { seen } = await setup($, on, { dirty: 'motivo=compact\n', cli: code })
    await $.turn.complete(DONE_TURN)
    await clock.advance(MIN + 1000)
    await $.turn.complete(DONE_TURN)
    await clock.advance(50)
    expect(seen.calls).toBe(code === 4 ? 2 : 1)
    expect(seen.toasts).toEqual([])
    expect(seen.logs.some(l => l.includes('autosave fallido'))).toBe(true)
    const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: /Handoff fallido|Guardado en/ })).toBeFalsy()
  })
}

test('autosave: con el 70 % visible en cola no se solapa; el handoff visible guarda una sola vez', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n', tokens: 30_000, live: false, env: '70' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  seen.tokens = 150_000
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  expect(seen.forks).toBe(0)
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  expect(seen.toasts.some(t => t.includes('handoff automático'))).toBe(true)
})

test('autosave: /handoff durante una síntesis silenciosa dice que está en curso, sin recibo viejo', async ($, on) => {
  const clock = mock.clock(on)
  let release = () => {}
  const hold = new Promise<void>(r => { release = r })
  const { seen } = await setup($, on, { dirty: 'motivo=compact\n', hold })
  await $.turn.complete(DONE_TURN)
  await clock.advance(MIN + 1000)
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  const r = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.text).toContain('guardado automático en curso')
  expect(seen.forks).toBe(0)
  release()
  await clock.advance(50)
  expect(seen.forks).toBe(1)
})

test('autosave: el +15 puntos cuenta desde el primer turno, aunque el contexto suba antes de pasar los topes', async ($, on) => {
  const clock = mock.clock(on)
  const { seen } = await setup($, on, { dirty: 'motivo=edit\n', tokens: 30_000 })
  await $.turn.complete(DONE_TURN)
  await clock.advance(50)
  seen.tokens = 80_000
  await clock.advance(11 * MIN)
  await turns($, clock, 4)
  expect(seen.forks).toBe(1)
  expect(seen.prompts).toHaveLength(1)
})
