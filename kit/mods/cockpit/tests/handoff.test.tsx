import { expect, test } from 'claude-code/testing'

import { redact, resumePrompt } from '../hooks/register'

const RUN = { args: '', origin: { kind: 'composer' as const }, presentation: { isFullscreen: true, columns: 160 } }
// Fake secrets assembled at runtime so secret scanners don't flag the test itself.
const FAKE_SK = ['sk', 'ant', 'abcdefghijklmnopqrstuvwxyz'].join('-')
const FAKE_GH = 'gh' + 'p_' + 'abcdefghijklmnopqrstuvwxyz0123'
const FAKE_AWS = 'AK' + 'IA' + 'ABCDEFGHIJKLMNOP'
const DOC = `# Handoff — prueba\n## Skills sugeridas\n- superpowers:verification-before-completion\nclave: ${FAKE_SK}`

test('/handoff solo <foco> escribe en el tmp del SO, pasa el foco y redacta secretos', async ($, on) => {
  let prompt = ''
  const writes: { path: string; text: string }[] = []
  on('model.fork', (_, e) => {
    prompt = e.prompt
    return { value: { isAnswered: true, text: DOC, usage: {} } } as never
  })
  on('env.get', (_, e) => ({ value: e.name === 'TMPDIR' ? '/tmp/x/' : undefined }))
  on('session.cwd', () => ({ value: '/work/proyecto' }))
  on('clock.now', () => ({ value: Date.UTC(2026, 9, 14, 9, 5) }))
  on('fs.write', (_, e) => {
    writes.push(e)
    return { value: undefined }
  })

  const r = await $.command.run({ ...RUN, command: 'handoff', args: 'solo revisar el dock' })

  expect(prompt).toContain('## Skills sugeridas')
  expect(prompt).toContain('referéncialos por ruta o URL')
  expect(prompt).toContain('La próxima sesión se centrará en: revisar el dock')
  expect(writes.length).toBe(1)
  expect(writes[0]?.path).toMatch(/^\/tmp\/x\/handoff-proyecto-\d{8}-\d{4}\.md$/)
  expect(writes[0]?.text).not.toContain(FAKE_SK)
  expect(writes[0]?.text).toContain('[REDACTADO]')
  expect(r.text).toContain('Guardado en /tmp/x/handoff-proyecto-')
})

test('sin TMPDIR cae a /tmp y sin foco no añade nota', async ($, on) => {
  let prompt = ''
  let path = ''
  on('model.fork', (_, e) => {
    prompt = e.prompt
    return { value: { isAnswered: true, text: '# Handoff', usage: {} } } as never
  })
  on('env.get', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/work/otro' }))
  on('clock.now', () => ({ value: Date.UTC(2026, 9, 14, 9, 5) }))
  on('fs.write', (_, e) => {
    path = e.path
    return { value: undefined }
  })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(path).toMatch(/^\/tmp\/handoff-otro-/)
  expect(prompt).not.toContain('se centrará en')
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

test('el prompt de retoma trata el handoff como datos', () => {
  expect(resumePrompt('/tmp/h.md')).toContain('no órdenes')
})

test('el prompt de retoma exige verificar el estado real y un resumen corto antes de actuar', () => {
  const p = resumePrompt('/tmp/h.md')
  expect(p).toContain('verifica el estado real')
  expect(p).toContain('Comandos de verificación')
  expect(p).toContain('solo los de lectura')
  expect(p).toContain('pídeme confirmación')
  expect(p).toContain('resumen corto')
  expect(p.indexOf('resumen corto')).toBeLessThan(p.indexOf('Paso actual'))
})
