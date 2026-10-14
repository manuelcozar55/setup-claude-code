import { expect, test, type TestBody } from 'claude-code/testing'

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
function repo(on: Parameters<TestBody>[1], files: Record<string, string>, opts: { isIgnored?: boolean; isRepo?: boolean } = {}) {
  const runs: Run[] = []
  const writes: { path: string; text: string }[] = []
  on('session.cwd', () => ({ value: '/work/proyecto/sub' }))
  on('process.run', (_, e) => {
    runs.push(e)
    const a = e.argv.join(' ')
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
