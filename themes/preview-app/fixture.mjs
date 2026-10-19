// The synthetic session the live preview resumes: a typical control-panel exchange, built in
// the record shape Claude Code 2.1.303 writes to ~/.claude/projects/*/<id>.jsonl. Every name,
// repo and number below is invented; nothing is copied from a real session.
const T0 = Date.parse('2026-10-19T09:00:00Z');

export function fixtureJsonl(cwd, sessionId) {
  const recs = [];
  let parent = null;
  const push = (type, extra) => {
    const uuid = `00000000-0000-4000-8000-${String(recs.length + 1).padStart(12, '0')}`;
    recs.push({ parentUuid: parent, isSidechain: false, type, uuid, timestamp: new Date(T0 + recs.length * 7000).toISOString(),
      userType: 'external', entrypoint: 'cli', cwd, sessionId, version: '2.1.303', gitBranch: 'main', ...extra });
    parent = uuid;
  };
  const user = (content, extra = {}) => push('user', { message: { role: 'user', content }, ...extra });
  const say = (content) => push('assistant', { message: { id: `msg_fx${recs.length}`, type: 'message', role: 'assistant',
    model: 'claude-opus-5-5', content: typeof content === 'string' ? [{ type: 'text', text: content }] : content,
    stop_reason: typeof content === 'string' ? 'end_turn' : 'tool_use', stop_sequence: null,
    usage: { input_tokens: 10, output_tokens: 20, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 } } });
  const tool = (id, name, input, result, toolUseResult, isError = false) => {
    say([{ type: 'tool_use', id, name, input }]);
    user([{ tool_use_id: id, type: 'tool_result', content: result, is_error: isError }], { toolUseResult });
  };
  const task = `${cwd}/projects/billing-export/tasks/T-004.md`;
  const taskText = '---\nid: T-004\nstatus: in-progress\nrepo: widgets\n---\n# Export invoices as CSV\n\n# Notes\n- PR open, lint red\n';

  user("what's the state of the `billing-export` project?", { promptId: 'p1' });
  say("I'll read the task and check its PR.");
  tool('toolu_fx01', 'Read', { file_path: task }, taskText,
    { type: 'text', file: { filePath: task, content: taskText, numLines: 9, startLine: 1, totalLines: 9 } });
  const checks = 'Exit code 1\nsrc/export.ts:41:10  error  \'formatRow\' is defined but never used  no-unused-vars\n✖ 1 problem (1 error, 0 warnings)';
  tool('toolu_fx02', 'Bash', { command: 'npm run lint', description: 'Reproduce the red lint check' },
    checks, `Error: ${checks}`, true);
  const verdict = 'Root cause: `formatRow` is imported but unused after the refactor. Fix: drop the import.';
  tool('toolu_fx03', 'Agent', { description: 'Diagnose the lint failure', subagent_type: 'failure-analyst', prompt: 'Diagnose the red lint check on widgets#81.' },
    [{ type: 'text', text: verdict }],
    { status: 'completed', prompt: 'Diagnose the red lint check on widgets#81.', agentId: 'a0fx03', agentType: 'failure-analyst',
      content: [{ type: 'text', text: verdict }], totalDurationMs: 41000, totalTokens: 12400, totalToolUseCount: 8,
      usage: { input_tokens: 10, output_tokens: 20, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 } });
  const [oldS, newS] = ['- PR open, lint red', '- PR open, lint red: unused `formatRow` import (fix dispatched)'];
  tool('toolu_fx04', 'Edit', { file_path: task, old_string: oldS, new_string: newS, replace_all: false },
    `The file ${task} has been updated successfully.`,
    { filePath: task, oldString: oldS, newString: newS, originalFile: taskText, userModified: false, replaceAll: false,
      structuredPatch: [{ oldStart: 7, oldLines: 3, newStart: 7, newLines: 3, lines: ['', ' # Notes', `-${oldS}`, `+${newS}`] }] });
  say([
    '**billing-export** is one fix away from review. CI on [widgets#81](https://github.com/example/widgets/pull/81) is red on lint only.',
    '',
    '| Task | Status | PR |',
    '|---|---|---|',
    '| T-003 Schema for `invoice_rows` | done | widgets#79 |',
    '| T-004 Export invoices as CSV | in-progress | widgets#81 |',
    '| T-005 Nightly export job | draft | — |',
    '',
    '- the lint failure is an unused import, `formatRow` in `src/export.ts:41`',
    '- tests pass (3m40s)',
    '',
    'ℹ️ **Needs you:**',
    '1. ⬆ prom T-005: acceptance criteria are filled in',
    '2. ✅ appr the CSV column order in T-004 # Notes',
  ].join('\n'));
  user('<bash-input>git log --oneline -2</bash-input>', { promptId: 'p2' });
  user('<bash-stdout>3f9c2ad chore(tick): 2026-10-19T08:58:10Z — idle\n81b07e4 feat(billing-export): T-004 criteria</bash-stdout><bash-stderr></bash-stderr>', { promptId: 'p2' });
  user('<bash-input>npm run lint</bash-input>', { promptId: 'p3' });
  user("<bash-stdout></bash-stdout><bash-stderr>src/export.ts:41:10  error  'formatRow' is defined but never used</bash-stderr>", { promptId: 'p3' });
  user('1 prom', { promptId: 'p4' });
  say('Promoted **T-005** to `ready`. The next tick dispatches it.');
  return `${recs.map((r) => JSON.stringify(r)).join('\n')}\n`;
}
