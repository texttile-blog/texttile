export const meta = {
  name: 'review-pr',
  description: 'Parallel multi-dimension review of an open PR with adversarial verification of findings',
  whenToUse: 'Invoked by the /review-pr skill for substantial PRs',
  phases: [
    { title: 'Review', detail: 'one agent per review dimension' },
    { title: 'Verify', detail: 'adversarial check of each finding' },
  ],
}

const pr = args && args.pr ? `PR #${args.pr}` : 'the PR belonging to the current branch'
// Free-text context for the agents, e.g. the worktree path where the branch is checked out.
const ctx = args && args.context ? `\n\nContext: ${args.context}` : ''

const FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'title', 'description', 'severity'],
        properties: {
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'number' },
          title: { type: 'string', description: 'one-line claim' },
          description: { type: 'string', description: 'what is wrong and the concrete failure scenario' },
          severity: { enum: ['critical', 'major', 'minor'] },
        },
      },
    },
  },
}

const VERDICT = {
  type: 'object',
  required: ['real', 'reasoning'],
  properties: {
    real: { type: 'boolean' },
    reasoning: { type: 'string' },
  },
}

// Model per dimension: the two dimensions where subtle bugs hide (concurrency,
// security) get opus; the more mechanical checks run on sonnet.
const DIMENSIONS = [
  {
    key: 'correctness',
    model: 'opus',
    prompt: 'Bugs, unhandled edge cases, and race conditions. Multiplayer editing makes concurrency a first-class concern in this project.',
  },
  {
    key: 'tests',
    model: 'sonnet',
    prompt: 'TDD adherence: every piece of business logic needs a unit test, acceptance criteria need e2e coverage beyond the happy path, and nothing under test/contract/ may have been modified or weakened.',
  },
  {
    key: 'minimalism',
    model: 'sonnet',
    prompt: 'Anything removable: unnecessary abstractions, dead code, premature generality, dependencies that a few lines of code would replace. This project is only good when nothing more can be removed.',
  },
  {
    key: 'frontend-weight',
    model: 'sonnet',
    prompt: 'Data frugality is a core value: flag unnecessary JavaScript, oversized payloads, or assets shipped to the frontend that a remote-location user on a slow link would pay for.',
  },
  {
    key: 'security',
    model: 'opus',
    prompt: 'Auth, session handling, input validation, file uploads, and user-generated content (comments, markdown rendering): XSS, injection, path traversal, missing authorization checks.',
  },
]

const reviews = await parallel(DIMENSIONS.map(d => () =>
  agent(
    `Read AGENTS.md first. You are reviewing ${pr} in this repository, focused ONLY on this dimension: ${d.key}.\n\n${d.prompt}\n\nRead the full diff with \`gh pr diff\` and enough surrounding code (Read the actual files) to judge the changes in context, not just the changed lines. Report only real, actionable findings for your dimension. Do not pad the list; an empty list is a valid result.${ctx}`,
    { label: `review:${d.key}`, phase: 'Review', schema: FINDINGS, model: d.model }
  )
))

// Barrier is intentional: dedupe across all dimensions before paying for verification.
const seen = new Set()
const unique = []
for (const r of reviews.filter(Boolean)) {
  for (const f of r.findings) {
    const key = `${f.file}:${f.line || 0}:${f.title.toLowerCase()}`
    if (!seen.has(key)) {
      seen.add(key)
      unique.push(f)
    }
  }
}
log(`${unique.length} unique findings across ${reviews.filter(Boolean).length} dimensions`)

if (unique.length === 0) return { confirmed: [], unverified: [] }

const order = { critical: 0, major: 1, minor: 2 }
unique.sort((a, b) => order[a.severity] - order[b.severity])

const VERIFY_CAP = 12
const toVerify = unique.slice(0, VERIFY_CAP)
const unverified = unique.slice(VERIFY_CAP)
if (unverified.length > 0) log(`capping verification at ${VERIFY_CAP}; ${unverified.length} minor findings passed through unverified`)

const verified = await parallel(toVerify.map(f => () =>
  agent(
    `Adversarially verify this code-review finding on ${pr}. Your job is to try to REFUTE it by reading the actual code, not to agree with it.\n\nFile: ${f.file}${f.line ? ':' + f.line : ''}\nSeverity: ${f.severity}\nClaim: ${f.title}\n${f.description}\n\nRead the diff with \`gh pr diff\` and the surrounding files. Set real=true only if the problem genuinely exists as described and is worth fixing. If you are uncertain or the claim is speculative, set real=false and say why.${ctx}`,
    // Verification is a focused yes/no on one claim; sonnet is enough.
    { label: `verify:${f.file}`, phase: 'Verify', schema: VERDICT, model: 'sonnet' }
  ).then(v => (v && v.real ? { ...f, verification: v.reasoning } : null))
))

const confirmed = verified.filter(Boolean)
log(`${confirmed.length}/${toVerify.length} findings confirmed`)
return { confirmed, unverified }
