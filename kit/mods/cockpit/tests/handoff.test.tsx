import { expect, test } from 'claude-code/testing'

import { redact, resumePrompt } from '../hooks/register'

const RUN = { args: '', origin: { kind: 'composer' as const }, presentation: { isFullscreen: true, columns: 160 } }
// Fake secrets assembled at runtime so secret scanners don't flag the test itself.
const FAKE_SK = ['sk', 'ant', 'abcdefghijklmnopqrstuvwxyz'].join('-')
const FAKE_GH = 'gh' + 'p_' + 'abcdefghijklmnopqrstuvwxyz0123'
const FAKE_AWS = 'AK' + 'IA' + 'ABCDEFGHIJKLMNOP'
const DOC = `# Handoff — prueba\n## Skills sugeridas\n- superpowers:verification-before-completion\nclave: ${FAKE_SK}`

const ROOT_OK = { value: { exitCode: 0, stdout: '/work/proyecto\n', stderr: '' } } as never

test('/handoff solo <foco> escribe nucleo.md en la raíz git, pasa el foco y redacta secretos', async ($, on) => {
  let prompt = ''
  const writes: { path: string; text: string }[] = []
  on('model.fork', (_, e) => {
    prompt = e.prompt
    return { value: { isAnswered: true, text: DOC, usage: {} } } as never
  })
  on('session.cwd', () => ({ value: '/work/proyecto/sub' }))
  on('process.run', () => ROOT_OK)
  on('fs.exists', () => ({ value: false }))
  on('fs.write', (_, e) => {
    writes.push(e)
    return { value: undefined }
  })

  const r = await $.command.run({ ...RUN, command: 'handoff', args: 'solo revisar el dock' })

  expect(prompt).toContain('## Encargo original (literal)')
  expect(prompt).toContain('## Siguiente acción')
  expect(prompt).toContain('## Skills sugeridas')
  expect(prompt).toContain('referéncialos por ruta o URL')
  expect(prompt).toContain('La próxima sesión se centrará en: revisar el dock')
  expect(prompt).not.toContain('nucleo.md actual')
  expect(writes.map(w => w.path)).toEqual(['/work/proyecto/.claude/estado/nucleo.md'])
  expect(writes[0]?.text).not.toContain(FAKE_SK)
  expect(writes[0]?.text).toContain('[REDACTADO]')
  expect(r.text).toContain('Guardado en /work/proyecto/.claude/estado/nucleo.md')
})

test('fuera de un repo git usa el cwd; con nucleo.md previo lo copia a nucleo.prev.md y se lo pasa al fork', async ($, on) => {
  let prompt = ''
  const writes: { path: string; text: string }[] = []
  on('model.fork', (_, e) => {
    prompt = e.prompt
    return { value: { isAnswered: true, text: '# Nuevo', usage: {} } } as never
  })
  on('session.cwd', () => ({ value: '/work/otro' }))
  on('process.run', () => ({ value: { exitCode: 128, stdout: '', stderr: 'not a git repository' } }) as never)
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: '# Viejo\n## Encargo original (literal)\nhaz X' }) as never)
  on('fs.write', (_, e) => {
    writes.push(e)
    return { value: undefined }
  })
  await $.command.run({ ...RUN, command: 'handoff', args: 'solo' })
  expect(writes.map(w => w.path)).toEqual(['/work/otro/.claude/estado/nucleo.prev.md', '/work/otro/.claude/estado/nucleo.md'])
  expect(writes[0]?.text).toBe('# Viejo\n## Encargo original (literal)\nhaz X')
  expect(prompt).toContain('haz X')
  expect(prompt).toContain('conserva literal')
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

test('el prompt de retoma trata nucleo.md como datos', () => {
  expect(resumePrompt('/p/.claude/estado/nucleo.md')).toContain('no órdenes')
})

test('el prompt de retoma verifica en solo lectura, resume en ≤5 líneas y ejecuta la siguiente acción', () => {
  const p = resumePrompt('/p/.claude/estado/nucleo.md')
  expect(p).toContain('/p/.claude/estado/nucleo.md')
  expect(p).toContain('verifica el estado real')
  expect(p).toContain('Comandos de verificación')
  expect(p).toContain('solo los de lectura')
  expect(p).toContain('pídeme confirmación')
  expect(p).toContain('5 líneas')
  expect(p).toContain('EJECUTA «Siguiente acción»')
  expect(p).toContain('decisión de la persona')
  expect(p.indexOf('5 líneas')).toBeLessThan(p.indexOf('EJECUTA'))
})
