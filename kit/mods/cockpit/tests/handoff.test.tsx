import { expect, mock, test, type TestBody } from 'claude-code/testing'

import { mergeNucleo, redact } from '../hooks/register'

const RUN = { args: '', origin: { kind: 'composer' as const }, presentation: { isFullscreen: true, columns: 160 } }
// Fake secrets assembled at runtime so secret scanners don't flag the test itself.
const FAKE_SK = ['sk', 'ant', 'abcdefghijklmnopqrstuvwxyz'].join('-')
const FAKE_GH = 'gh' + 'p_' + 'abcdefghijklmnopqrstuvwxyz0123'
const FAKE_AWS = 'AK' + 'IA' + 'ABCDEFGHIJKLMNOP'
const EST = '/work/proyecto/.claude/estado'
const NEW = `## Encargo original (literal)\nhaz X\n## Invariantes\n- no tocar Y\n## Plan\n- [ ] T1\n## Siguiente acción\nT1\nclave: ${FAKE_SK}\n`
const PREV = '# Estado\n\n## Encargo original (literal)\nhaz X  \ntal cual\n\n## Invariantes y decisiones\n- no tocar Y\n## Plan\n- [ ] T1\n## Skills sugeridas\n- grilling\n'

type Run = { argv: readonly string[] }
const ok = (stdout = '') => ({ value: { exitCode: 0, stdout, stderr: '' } }) as never
const no = () => ({ value: { exitCode: 1, stdout: '', stderr: '' } }) as never

// A fake repo: git answers by argv, the files live in a map.
function repo(on: Parameters<TestBody>[1], files: Record<string, string>, opts: { isIgnored?: boolean; isRepo?: boolean; cwd?: string; home?: string; env?: string } = {}) {
  const runs: Run[] = []
  const writes: { path: string; text: string }[] = []
  on('session.cwd', () => ({ value: opts.cwd ?? '/work/proyecto/sub' }))
  on('process.run', (_, e) => {
    runs.push(e)
    const a = e.argv.join(' ')
    if (a === 'printenv HOME') return opts.home ? ok(opts.home) : no()
    if (a === 'printenv COCKPIT_AUTO_HANDOFF') return opts.env ? ok(opts.env) : no()
    if (a.includes('--show-toplevel')) return opts.isRepo === false ? no() : ok('/work/proyecto\n')
    if (a.includes('check-ignore')) return opts.isIgnored ? ok() : no()
    if (a.includes('--git-path')) return ok('.git/info/exclude\n')
    return ok()
  })
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }) as never)
  on('fs.list', () => ({ value: Object.keys(files).filter(p => p.startsWith(EST + '/')).map(p => ({ name: p.slice(EST.length + 1), kind: 'file' })) }) as never)
  on('fs.write', (_, e) => {
    writes.push(e)
    files[e.path] = e.text
    return { value: undefined }
  })
  return { runs, writes, files }
}

test('sin nucleo: el fork extrae encargo e invariantes, se crea el esqueleto, se redacta y se excluye .claude/estado/', async ($, on) => {
  let prompt = ''
  on('model.fork', (_, e) => {
    prompt = e.prompt
    return { value: { isAnswered: true, text: 'Aquí tienes:\n' + NEW, usage: {} } } as never
  })
  const r = repo(on, { '/work/proyecto/.git/info/exclude': '# git ls-files\n' })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo revisar el dock' })

  expect(prompt).toContain('Aún no hay nucleo.md')
  expect(prompt).toContain('## Ficheros tocados')
  expect(prompt).toContain('La próxima sesión se centrará en: revisar el dock')
  const doc = r.files[`${EST}/nucleo.md`] ?? ''
  expect(doc).toContain('## Encargo original (literal)\nhaz X\n')
  expect(doc).not.toContain('Aquí tienes')
  expect(doc).not.toContain(FAKE_SK)
  expect(doc).toContain('[REDACTADO]')
  expect(r.writes.some(w => w.path.includes('nucleo.prev-'))).toBe(false)
  expect(r.files['/work/proyecto/.git/info/exclude']).toBe('# git ls-files\n.claude/estado/\n')
  expect(res.text).toContain(`Guardado en ${EST}/nucleo.md`)
})

test('con nucleo: fusiona solo lo mutable, conserva encargo e invariantes byte a byte y guarda copia sellada', async ($, on) => {
  let prompt = ''
  on('model.fork', (_, e) => {
    prompt = e.prompt
    return { value: { isAnswered: true, text: '## Encargo original (literal)\nOTRO\n## Plan\n- [x] T1 (make test, exit 0)\n## Ficheros tocados\n- /a\n', usage: {} } } as never
  })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })

  expect(prompt).toContain('haz X')
  expect(prompt).toContain('no los devuelvas')
  expect(prompt).not.toContain('Aún no hay nucleo.md')
  const doc = r.files[`${EST}/nucleo.md`] ?? ''
  expect(doc).toContain('## Encargo original (literal)\nhaz X  \ntal cual\n\n## Invariantes y decisiones\n- no tocar Y\n')
  expect(doc).not.toContain('OTRO')
  expect(doc).toContain('- [x] T1 (make test, exit 0)')
  expect(doc).toContain('## Skills sugeridas\n- grilling\n')
  expect(doc).toContain('## Ficheros tocados\n- /a\n')
  const copy = r.writes.find(w => /\/nucleo\.prev-\d{8}T\d{6}Z?\.md$/.test(w.path))
  expect(copy?.text).toBe(PREV)
  expect(r.runs.some(x => x.argv.includes('--git-path'))).toBe(false)
})

test('guarda solo las 3 copias más recientes', async ($, on) => {
  on('model.fork', () => ({ value: { isAnswered: true, text: '## Plan\n- [ ] T2\n', usage: {} } }) as never)
  const old = ['20261001T000000', '20261002T000000', '20261003T000000', '20261004T000000'].map(s => `${EST}/nucleo.prev-${s}.md`)
  const r = repo(on, Object.fromEntries([[`${EST}/nucleo.md`, PREV], ...old.map(p => [p, 'x'])]), { isIgnored: true })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  const rm = r.runs.find(x => x.argv[0] === 'rm')
  expect(rm?.argv.slice(-2)).toEqual([old[0], old[1]])
})

test('una respuesta sin secciones no toca nucleo.md', async ($, on) => {
  on('model.fork', () => ({ value: { isAnswered: true, text: 'No puedo.', usage: {} } }) as never)
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  const res = await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.writes).toEqual([])
  expect(res.text).toContain('Handoff fallido')
})

test('fuera de un repo git usa el cwd y no toca .git', async ($, on) => {
  on('model.fork', () => ({ value: { isAnswered: true, text: NEW, usage: {} } }) as never)
  const r = repo(on, {}, { isRepo: false })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(r.writes.map(w => w.path)).toEqual(['/work/proyecto/sub/.claude/estado/nucleo.md'])
  expect(r.runs.some(x => x.argv.includes('check-ignore'))).toBe(false)
})

test('raíz como nucleo_raiz: git desde el cwd de la sesión, y $HOME/.claude/** sube a $HOME', async ($, on) => {
  on('model.fork', () => ({ value: { isAnswered: true, text: NEW, usage: {} } }) as never)
  const runs: Run[] = []
  const paths: string[] = []
  on('session.cwd', () => ({ value: '/h/.claude/estado' }))
  on('process.run', (_, e) => {
    runs.push(e)
    const a = e.argv.join(' ')
    if (a.includes('--show-toplevel')) return ok('/h/.claude\n')
    if (a === 'printenv HOME') return ok('/h\n')
    if (a.includes('--git-path')) return ok('.git/info/exclude\n')
    return no()
  })
  on('fs.exists', () => ({ value: false }))
  on('fs.read', () => ({ value: '' }) as never)
  on('fs.list', () => ({ value: [] }) as never)
  on('fs.write', (_, e) => { paths.push(e.path); return { value: undefined } })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(runs.find(x => x.argv.includes('--show-toplevel'))?.argv.slice(0, 3)).toEqual(['git', '-C', '/h/.claude/estado'])
  expect(paths).toContain('/h/.claude/estado/nucleo.md')
  expect(paths.some(p => p.startsWith('/h/.claude/.claude/'))).toBe(false)
})

test('mergeNucleo: secciones nuevas al final, inmutables ignoradas y sin salto perdido', () => {
  const prev = '# T\n## Invariantes\n- a'
  expect(mergeNucleo(prev, '## Invariantes\n- b\n## Paso actual\nT3\n')).toBe('# T\n## Invariantes\n- a\n## Paso actual\nT3\n')
})

test('redact tapa claves conocidas y asignaciones, y deja el resto', () => {
  expect(redact(`token: ${FAKE_GH}`)).toBe('token: [REDACTADO]')
  expect(redact(`password=hunter2 y ${FAKE_AWS}`)).toBe('password=[REDACTADO] y [REDACTADO]')
  expect(redact('ver /tmp/handoff.md y el commit abc123')).toBe('ver /tmp/handoff.md y el commit abc123')
})

test('redact cubre Bearer, claves privadas, URLs con credenciales, pat de GitHub/GitLab y JSON', () => {
  const pem = '-----BEGIN ' + 'RSA PRIVATE KEY-----\nabc\ndef\n-----END ' + 'RSA PRIVATE KEY-----'
  expect(redact('Authorization: Bearer ' + 'abc.def-123')).toBe('Authorization: Bearer [REDACTADO]')
  expect(redact(`antes\n${pem}\ndespues`)).toBe('antes\n[REDACTADO]\ndespues')
  expect(redact('git clone https://' + 'user:pa55@host/repo.git')).toBe('git clone https://[REDACTADO]@host/repo.git')
  expect(redact('github_' + 'pat_' + 'abcdefghijklmnopqrstuvwxyz')).toBe('[REDACTADO]')
  expect(redact('gl' + 'pat-' + 'abcdefghijklmnopqrstuvwxyz')).toBe('[REDACTADO]')
  expect(redact('{"password": "hunter 2", "ok": 1}')).toBe('{"password": [REDACTADO], "ok": 1}')
  expect(redact("secret='dos palabras' fin")).toBe("secret=[REDACTADO] fin")
})

// ── Automatic handoff, compaction veto and /nueva
const DONE_TURN = { answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' as const }
const FILL = 'sigue con la Siguiente acción de .claude/estado/nucleo.md'
const PLAN = '## Plan\n- [ ] T2\n## Siguiente acción\nT2\n'

// The context read is throttled by the clock (it starts at 0), so tests that read it twice start it at 10 s.
// The engine beneath the mod: usage (limit 180k = 200k - 20k buffer), agents, fork, clear and fill.
function auto(
  on: Parameters<TestBody>[1],
  o: { tokens: number; window?: number; agents?: { id: string; status: string }[]; usageFailsAfter?: number; forkText?: string },
) {
  const seen = { forks: 0, cleared: 0, fills: [] as string[], toasts: [] as string[], usageCalls: 0 }
  on('session.usage', () => {
    if (o.usageFailsAfter !== undefined && ++seen.usageCalls > o.usageFailsAfter) throw new Error('usage caído')
    return {
    value: {
      startedAt: 0,
      rateLimits: [],
      context: {
        tokens: o.tokens,
        window: o.window ?? 1_000_000,
        breakdown: { totalTokens: o.tokens, rawMaxTokens: 200_000, categories: [{ kind: 'buffer', name: 'Autocompact buffer', tokens: 20_000 }] },
      },
    },
    } as never
  })
  on('agent.list', () => ({ value: (o.agents ?? []).map(a => ({ ...a, description: '', type: 'x' })) }) as never)
  on('model.fork', () => {
    seen.forks++
    return { value: { isAnswered: true, text: o.forkText ?? PLAN, usage: {} } } as never
  })
  on('command.run', (_, e) => {
    if (e.command === 'clear') seen.cleared++
    return { text: '' }
  })
  on('prompt.fill', (_, e) => {
    seen.fills.push(e.text)
    return { isFilled: true } as never
  })
  on('turn.complete', (_, e) => ({ text: e.answer }) as never)
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('session.compact', () => ({ messages: [SUMMARY] }) as never)
  on('ui.toast', (_, e) => {
    seen.toasts.push(e.text)
    return { value: undefined } as never
  })
  return seen
}

test('handoff automático: en un repo, al cruzar el umbral, guarda, limpia y rellena el prompt', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete(DONE_TURN)
  expect(seen.forks).toBe(0)
  await clock.advance(400)
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  expect(r.files[`${EST}/nucleo.md`]).toContain('T2')
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual([FILL])
  expect(seen.toasts.some(t => t.includes('handoff automático'))).toBe(true)
})

test('handoff automático: con un subagente vivo no dispara', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000, agents: [{ id: 'a1', status: 'running' }] })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: sin disparo con COCKPIT_AUTO_HANDOFF=off', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true, env: 'off' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: un umbral más alto (90) no dispara al 72 %', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true, env: '90' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: un valor inválido vale 70', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true, env: 'mucho' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(1)
})

test('handoff automático: bajo el umbral no dispara', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 100_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: un subagente no lo dispara', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete({ ...DONE_TURN, agentId: 'a1' })
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: en $HOME (nucleo compartido) queda desactivado', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(0)
})

test('handoff automático: si empieza otro turno entre el handoff y el clear, no limpia y lo dice', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete(DONE_TURN)
  await clock.advance(400)
  await $.turn.start({ text: 'otra cosa', turnId: 't2' })
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  expect(seen.cleared).toBe(0)
  const ui = await $.ui.mount({ plugin: 'cockpit', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 110, scroll: { offset: 0, bodyRows: 20 }, view: {} } })
  expect(await ui.find({ text: /empezó otro turno/ })).toBeTruthy()
})

const SUMMARY = { role: 'user' as const, text: 'resumen', toolUses: [] }
const COMPACT = { trigger: 'auto' as const, messages: [SUMMARY] }

test('veto: la compactación auto bajo el techo se salta, y el handoff dispara aunque el % sea bajo', async ($, on) => {
  const clock = mock.clock(on, { now: 10_000 })
  const seen = auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  const res = await $.session.compact(COMPACT as never)
  expect(res.skip).toMatch(/130K.*270K/)
  expect(seen.forks).toBe(0)
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(1)
})

test('veto: sobre el techo (1,5 × el umbral) la compactación sigue su curso', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 280_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: el techo no pasa de la mitad de la ventana real del modelo', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 110_000, window: 200_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: no se veta a un subagente, ni con off, ni en $HOME', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  expect((await $.session.compact({ ...COMPACT, agentId: 'a1' } as never)).skip).toBeUndefined()
})

test('veto: no se veta con off', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 130_000 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true, env: 'off' })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: no se veta en $HOME', async ($, on) => {
  mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 130_000 })
  repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: si la lectura del contexto falla, compacta en vez de vetar con el dato del turno anterior', async ($, on) => {
  const clock = mock.clock(on, { now: 10_000 })
  auto(on, { tokens: 100_000, usageFailsAfter: 1 })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('veto: con el handoff en error no se veta, porque el handoff ya no llegaría', async ($, on) => {
  const clock = mock.clock(on, { now: 10_000 })
  const seen = auto(on, { tokens: 130_000, forkText: 'No puedo.' })
  repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.complete(DONE_TURN)
  await clock.advance(800)
  expect(seen.forks).toBe(1)
  expect((await $.session.compact(COMPACT as never)).skip).toBeUndefined()
})

test('/nueva: con un turno en marcha no archiva ni limpia, y lo dice', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  await $.turn.start({ text: 'otra cosa', turnId: 't2' })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'arreglar el login' })
  await clock.advance(400)
  expect(seen.forks + seen.cleared).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
  expect(res.text).toContain('en marcha')
})

test('/nueva: archiva el nucleo, limpia y rellena el prompt con la tarea', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'arreglar el login' })
  await clock.advance(400)
  expect(seen.forks).toBe(1)
  const mv = r.runs.find(x => x.argv[0] === 'mv')
  expect(mv?.argv[mv.argv.length - 2]).toBe(`${EST}/nucleo.md`)
  expect(mv?.argv[mv.argv.length - 1]).toMatch(/\/estado\/archivo\/nucleo-\d{8}T\d{6}Z?\.md$/)
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual(['arreglar el login'])
  expect(res.text).toContain('archivo/')
})

test('/nueva: sin texto devuelve la ayuda y no toca nada', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, { [`${EST}/nucleo.md`]: PREV }, { isIgnored: true })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: '  ' })
  await clock.advance(400)
  expect(res.text).toContain('/nueva <')
  expect(seen.forks + seen.cleared).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
})

test('/nueva: en $HOME no hay handoff ni archivo, solo /clear y la tarea, con el aviso', async ($, on) => {
  const clock = mock.clock(on)
  const seen = auto(on, { tokens: 1000 })
  const r = repo(on, {}, { isRepo: false, cwd: '/h', home: '/h' })
  const res = await $.command.run({ ...RUN, command: 'nueva', args: 'otra cosa' })
  await clock.advance(400)
  expect(seen.forks).toBe(0)
  expect(r.runs.some(x => x.argv[0] === 'mv')).toBe(false)
  expect(seen.cleared).toBe(1)
  expect(seen.fills).toEqual(['otra cosa'])
  expect(res.text).toContain('~')
})
