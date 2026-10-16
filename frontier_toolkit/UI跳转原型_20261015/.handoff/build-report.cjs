const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const read = file => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const source = read('.handoff/source-verification.json');
const gpu = read('Tests/TA/validation_gpu.json');
const headless = read('Tests/TA/validation_headless.json');
const baselineFile = fs.existsSync(path.join(root, 'Tests/.runtime/headless_results.json')) ? 'Tests/.runtime/headless_results.json' : 'Tests/.runtime/build_results.json';
const baseline = read(baselineFile).filter(suite => suite.suite !== 'TA_SHADER_VALIDATION');
const expected = [
  ['SUMMON_V2_VALIDATION', 697], ['RITUAL_PRESENTATION_VALIDATION', 792],
  ['COMPONENT_CONTRACT_VALIDATION', 29], ['EVENT_PANEL_VALIDATION', 26],
  ['EVENT_LIFECYCLE_VALIDATION', 15], ['TASKS_VALIDATION', 31],
  ['FILTER_TABS_VALIDATION', 40], ['SCROLL_PRESENTATION_VALIDATION', 36],
  ['NESTED_MODAL_VALIDATION', 22], ['LOCATION_HINT_VALIDATION', 61]
];
if (baseline.length !== expected.length || source.sourceChanges.length || gpu.failures.length || headless.failures.length) throw new Error('Incomplete validation evidence');
const upstream = baseline.map((suite, index) => {
  if (suite.failures !== 0 || suite.checks !== expected[index][1]) throw new Error('Baseline mismatch');
  return {suite: expected[index][0], checks: suite.checks, failures: 0, renderer: 'headless'};
});
const motion = read('Tests/.runtime/capture_results.json').find(suite => suite.suite.endsWith('_MOTION_VALIDATION'));
if (!motion || motion.failures || motion.checks !== 40) throw new Error('A2 renderer verification missing');
upstream.push({suite: 'A2_MOTION_VALIDATION', checks: motion.checks, failures: 0, renderer: 'gl_compatibility'});
const report = {
  date: '2026-10-15', repository: source.repository, commit: source.commit,
  sourceFiles: source.sourceFiles, sourceChanges: source.sourceChanges,
  engine: gpu.engine, renderer: gpu.renderer,
  device: 'Windows / OpenGL 3.3 / NVIDIA GeForce RTX 4070 SUPER',
  upstreamChecks: upstream.reduce((sum, suite) => sum + suite.checks, 0),
  upstreamSuites: upstream,
  shaderHeadlessChecks: headless.checks, shaderGpuChecks: gpu.checks,
  shaderFailures: gpu.failures, screenshots: gpu.screenshots,
  layoutResolutions: ['1120x680', '1280x720', '1920x1080'],
  notes: ['Shader checks overlap between headless and GPU runs; do not add them as unique cases.', 'All tracked upstream source bytes were preserved. TA/test/tool additions are separate.', 'No mobile-device performance claim.']
};
fs.writeFileSync(path.join(root, 'TA/VALIDATION.json'), JSON.stringify(report, null, 2) + '\n');
const referenceRoot = path.join(root, '.handoff/references');
const references = fs.readdirSync(referenceRoot).filter(name => /\.(md|jpg)$/.test(name)).map(name => {
  const data = fs.readFileSync(path.join(referenceRoot, name));
  return {file: name, source: 'References参考资料、怪物设计/美术参考图片/Shader效果对照/' + (name === '需求案.md' ? 'UI_Shader材质需求案_2026-10-13.md' : name), gitBlob: crypto.createHash('sha1').update('blob ' + data.length + '\0').update(data).digest('hex')};
});
fs.writeFileSync(path.join(referenceRoot, 'source.json'), JSON.stringify({repository: source.repository, commit: source.commit, files: references}, null, 2) + '\n');
console.log(JSON.stringify({upstream: report.upstreamChecks, shaderHeadless: headless.checks, shaderGpu: gpu.checks, screenshots: gpu.screenshots.length, sourceChanges: source.sourceChanges.length}));
