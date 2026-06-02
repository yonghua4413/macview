const canvas = document.querySelector('#game');
const ctx = canvas.getContext('2d');
const soundButton = document.querySelector('#soundToggle');

const W = canvas.width;
const H = canvas.height;
const WORLD_W = 4200;
const GROUND_Y = 454;
const keys = new Set();
const touchActions = new Set();
let last = performance.now();
let cameraX = 0;
let shake = 0;
let gameOver = false;
let won = false;

const player = {
  x: 90,
  y: GROUND_Y - 58,
  w: 34,
  h: 58,
  vx: 0,
  vy: 0,
  facing: 1,
  hp: 5,
  lives: 3,
  invuln: 0,
  cooldown: 0,
  onGround: false,
  score: 0,
};

const bullets = [];
const enemyBullets = [];
const particles = [];

const platforms = [
  { x: 560, y: 360, w: 230, h: 22 },
  { x: 1040, y: 314, w: 260, h: 22 },
  { x: 1540, y: 370, w: 280, h: 22 },
  { x: 2160, y: 318, w: 300, h: 22 },
  { x: 2860, y: 350, w: 340, h: 22 },
];

const enemies = [
  grunt(420, GROUND_Y - 42, 0), grunt(760, 318, 1), turret(1180, 278),
  grunt(1460, GROUND_Y - 42, 1), runner(1780, GROUND_Y - 44), turret(2280, 282),
  grunt(2520, GROUND_Y - 42, 0), runner(2840, GROUND_Y - 44), grunt(3190, 308, 1),
  turret(3380, GROUND_Y - 48), bunker(3880, GROUND_Y - 118),
];

function grunt(x, y, dir) {
  return { type: 'grunt', x, y, originX: x, w: 34, h: 42, hp: 2, vx: dir ? -30 : 30, shoot: 1.2, alive: true };
}

function runner(x, y) {
  return { type: 'runner', x, y, originX: x, w: 36, h: 44, hp: 3, vx: -78, shoot: 9, alive: true };
}

function turret(x, y) {
  return { type: 'turret', x, y, w: 42, h: 48, hp: 4, vx: 0, shoot: 0.7, alive: true };
}

function bunker(x, y) {
  return { type: 'bunker', x, y, w: 124, h: 118, hp: 26, vx: 0, shoot: 0.45, alive: true, boss: true };
}

const audio = {
  ctx: null,
  musicTimer: null,
  enabled: false,
  step: 0,
  melody: [196, 247, 294, 247, 330, 294, 247, 220, 196, 247, 330, 392, 330, 294, 247, 220],
  init() {
    if (!this.ctx) this.ctx = new AudioContext();
    if (this.ctx.state === 'suspended') this.ctx.resume();
  },
  toggle() {
    this.init();
    this.enabled = !this.enabled;
    soundButton.setAttribute('aria-pressed', String(this.enabled));
    soundButton.textContent = this.enabled ? '关闭音乐' : '开启音乐';
    if (this.enabled) this.startMusic();
    else this.stopMusic();
  },
  startMusic() {
    this.stopMusic();
    this.musicTimer = setInterval(() => {
      if (!this.enabled) return;
      const note = this.melody[this.step++ % this.melody.length];
      this.tone(note, 0.09, 'square', 0.045);
      if (this.step % 2 === 0) this.tone(98, 0.06, 'sawtooth', 0.035);
      if (this.step % 4 === 0) this.noise(0.035, 0.08);
    }, 145);
  },
  stopMusic() {
    if (this.musicTimer) clearInterval(this.musicTimer);
    this.musicTimer = null;
  },
  tone(freq, len = 0.06, type = 'square', vol = 0.05) {
    if (!this.enabled || !this.ctx) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = type;
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(vol, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + len);
    osc.connect(gain).connect(this.ctx.destination);
    osc.start();
    osc.stop(this.ctx.currentTime + len);
  },
  noise(len = 0.05, vol = 0.08) {
    if (!this.enabled || !this.ctx) return;
    const buffer = this.ctx.createBuffer(1, this.ctx.sampleRate * len, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    const source = this.ctx.createBufferSource();
    const gain = this.ctx.createGain();
    source.buffer = buffer;
    gain.gain.setValueAtTime(vol, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + len);
    source.connect(gain).connect(this.ctx.destination);
    source.start();
  },
};

soundButton.addEventListener('click', () => audio.toggle());
canvas.addEventListener('pointerdown', () => audio.init());

window.addEventListener('keydown', (event) => {
  keys.add(event.key.toLowerCase());
  if ([' ', 'arrowup', 'arrowleft', 'arrowright'].includes(event.key.toLowerCase())) event.preventDefault();
  if ((gameOver || won) && event.key.toLowerCase() === 'r') reset();
});
window.addEventListener('keyup', (event) => keys.delete(event.key.toLowerCase()));

document.querySelectorAll('.mobile-controls button').forEach((button) => {
  const action = button.dataset.action;
  button.addEventListener('pointerdown', () => touchActions.add(action));
  button.addEventListener('pointerup', () => touchActions.delete(action));
  button.addEventListener('pointerleave', () => touchActions.delete(action));
});

function pressed(...names) {
  return names.some((name) => keys.has(name) || touchActions.has(name));
}

function reset() {
  Object.assign(player, { x: 90, y: GROUND_Y - 58, vx: 0, vy: 0, hp: 5, lives: 3, invuln: 0, score: 0 });
  bullets.length = 0;
  enemyBullets.length = 0;
  particles.length = 0;
  enemies.length = 0;
  enemies.push(
    grunt(420, GROUND_Y - 42, 0), grunt(760, 318, 1), turret(1180, 278),
    grunt(1460, GROUND_Y - 42, 1), runner(1780, GROUND_Y - 44), turret(2280, 282),
    grunt(2520, GROUND_Y - 42, 0), runner(2840, GROUND_Y - 44), grunt(3190, 308, 1),
    turret(3380, GROUND_Y - 48), bunker(3880, GROUND_Y - 118),
  );
  gameOver = false;
  won = false;
}

function update(dt) {
  if (gameOver || won) return;
  player.cooldown = Math.max(0, player.cooldown - dt);
  player.invuln = Math.max(0, player.invuln - dt);
  const left = pressed('a', 'arrowleft', 'left');
  const right = pressed('d', 'arrowright', 'right');
  const jump = pressed('w', 'arrowup', ' ', 'jump');
  const fire = pressed('j', 'k', 'enter', 'fire');

  player.vx = (right ? 175 : 0) - (left ? 175 : 0);
  if (player.vx !== 0) player.facing = Math.sign(player.vx);
  if (jump && player.onGround) {
    player.vy = -420;
    player.onGround = false;
    audio.tone(440, 0.08, 'triangle', 0.04);
  }
  if (fire && player.cooldown <= 0) shootPlayer();

  player.vy += 920 * dt;
  player.x = Math.max(20, Math.min(WORLD_W - player.w - 40, player.x + player.vx * dt));
  moveVertical(player, dt);
  cameraX = Math.max(0, Math.min(WORLD_W - W, player.x - 270));

  bullets.forEach((b) => b.x += b.vx * dt);
  enemyBullets.forEach((b) => { b.x += b.vx * dt; b.y += b.vy * dt; });
  pruneProjectiles();

  enemies.forEach((e) => updateEnemy(e, dt));
  collideShots();
  collidePlayer();
  updateParticles(dt);
  shake = Math.max(0, shake - dt * 10);
  if (enemies.find((e) => e.boss)?.alive === false) won = true;
}

function moveVertical(obj, dt) {
  obj.y += obj.vy * dt;
  obj.onGround = false;
  if (obj.y + obj.h >= GROUND_Y) {
    obj.y = GROUND_Y - obj.h;
    obj.vy = 0;
    obj.onGround = true;
  }
  for (const p of platforms) {
    const falling = obj.vy >= 0;
    if (falling && obj.x + obj.w > p.x && obj.x < p.x + p.w && obj.y + obj.h > p.y && obj.y + obj.h < p.y + p.h + 22) {
      obj.y = p.y - obj.h;
      obj.vy = 0;
      obj.onGround = true;
    }
  }
}

function shootPlayer() {
  player.cooldown = 0.16;
  bullets.push({ x: player.x + player.w / 2 + player.facing * 22, y: player.y + 21, vx: player.facing * 610, w: 15, h: 5 });
  audio.tone(760, 0.045, 'square', 0.035);
}

function updateEnemy(e, dt) {
  if (!e.alive) return;
  const active = Math.abs(e.x - player.x) < 860 || e.boss;
  if (!active) return;
  if (e.type === 'grunt' || e.type === 'runner') {
    e.x += e.vx * dt;
    const min = e.type === 'runner' ? e.originX - 260 : e.originX - 90;
    const max = e.type === 'runner' ? e.originX + 260 : e.originX + 90;
    if (e.x < min || e.x > max) e.vx *= -1;
  }
  e.shoot -= dt;
  if (e.shoot <= 0) {
    const dx = player.x - e.x;
    const speed = e.boss ? 270 : 235;
    enemyBullets.push({ x: e.x + e.w / 2, y: e.y + e.h * 0.42, vx: Math.sign(dx || -1) * speed, vy: e.boss ? (Math.random() - 0.2) * 120 : 0, w: 10, h: 6 });
    e.shoot = e.boss ? 0.45 : 1.3 + Math.random() * 0.9;
    audio.tone(170, 0.045, 'sawtooth', 0.025);
  }
}

function pruneProjectiles() {
  for (let i = bullets.length - 1; i >= 0; i--) {
    if (bullets[i].x < cameraX - 80 || bullets[i].x > cameraX + W + 80) bullets.splice(i, 1);
  }
  for (let i = enemyBullets.length - 1; i >= 0; i--) {
    const b = enemyBullets[i];
    if (b.x < cameraX - 120 || b.x > cameraX + W + 120 || b.y > H) enemyBullets.splice(i, 1);
  }
}

function collideShots() {
  for (let bi = bullets.length - 1; bi >= 0; bi--) {
    const b = bullets[bi];
    for (const e of enemies) {
      if (e.alive && hit(b, e)) {
        bullets.splice(bi, 1);
        e.hp -= 1;
        burst(b.x, b.y, '#ffd45a', 8);
        if (e.hp <= 0) {
          e.alive = false;
          player.score += e.boss ? 5000 : 500;
          burst(e.x + e.w / 2, e.y + e.h / 2, '#ff6b40', e.boss ? 60 : 22);
          shake = e.boss ? 1.8 : 0.8;
          audio.noise(e.boss ? 0.45 : 0.16, e.boss ? 0.18 : 0.11);
        }
        break;
      }
    }
  }
}

function collidePlayer() {
  for (let i = enemyBullets.length - 1; i >= 0; i--) {
    if (hit(player, enemyBullets[i])) {
      enemyBullets.splice(i, 1);
      hurtPlayer();
    }
  }
  enemies.forEach((e) => { if (e.alive && hit(player, e)) hurtPlayer(); });
}

function hurtPlayer() {
  if (player.invuln > 0) return;
  player.hp -= 1;
  player.invuln = 1.1;
  shake = 1.2;
  burst(player.x + player.w / 2, player.y + player.h / 2, '#53d6ff', 18);
  audio.noise(0.16, 0.15);
  if (player.hp <= 0) {
    player.lives -= 1;
    player.hp = 5;
    player.x = Math.max(80, cameraX + 80);
    player.y = GROUND_Y - player.h;
    if (player.lives < 0) gameOver = true;
  }
}

function hit(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

function burst(x, y, color, count) {
  for (let i = 0; i < count; i++) {
    particles.push({ x, y, vx: (Math.random() - 0.5) * 260, vy: (Math.random() - 0.8) * 240, life: 0.5 + Math.random() * 0.4, color });
  }
}

function updateParticles(dt) {
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.life -= dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vy += 550 * dt;
    if (p.life <= 0) particles.splice(i, 1);
  }
}

function draw() {
  ctx.save();
  const wobble = shake > 0 ? (Math.random() - 0.5) * shake * 8 : 0;
  ctx.translate(wobble, 0);
  drawBackground();
  ctx.translate(-cameraX, 0);
  drawWorld();
  drawEntities();
  ctx.restore();
  drawHud();
  if (gameOver || won) drawOverlay();
}

function drawBackground() {
  const grad = ctx.createLinearGradient(0, 0, 0, H);
  grad.addColorStop(0, '#5bb4df');
  grad.addColorStop(0.52, '#8fd7ba');
  grad.addColorStop(1, '#20351f');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, W, H);
  drawSun();
  drawParallax('#276c54', 0.18, 330, 150, 16);
  drawParallax('#1e5740', 0.34, 380, 120, 12);
  drawParallax('#123a2a', 0.62, 424, 80, 9);
}

function drawSun() {
  ctx.fillStyle = 'rgba(255, 220, 112, 0.85)';
  ctx.beginPath();
  ctx.arc(760 - cameraX * 0.05, 94, 48, 0, Math.PI * 2);
  ctx.fill();
}

function drawParallax(color, factor, base, height, count) {
  ctx.fillStyle = color;
  for (let i = -1; i < count; i++) {
    const x = ((i * 190 - cameraX * factor) % (count * 190)) - 120;
    ctx.beginPath();
    ctx.moveTo(x, base);
    ctx.lineTo(x + 86, base - height - (i % 3) * 22);
    ctx.lineTo(x + 186, base);
    ctx.closePath();
    ctx.fill();
  }
}

function drawWorld() {
  ctx.fillStyle = '#16291d';
  ctx.fillRect(0, GROUND_Y, WORLD_W, H - GROUND_Y);
  ctx.fillStyle = '#6b4f2d';
  ctx.fillRect(0, GROUND_Y + 22, WORLD_W, 64);
  for (let x = 0; x < WORLD_W; x += 64) {
    ctx.fillStyle = x % 128 === 0 ? '#2d6a35' : '#22582e';
    ctx.fillRect(x, GROUND_Y - 12, 58, 16);
    ctx.fillStyle = '#0f351f';
    ctx.fillRect(x + 8, GROUND_Y - 24, 18, 20);
  }
  platforms.forEach(drawPlatform);
  for (let x = 260; x < WORLD_W; x += 310) drawPalm(x, GROUND_Y);
}

function drawPlatform(p) {
  ctx.fillStyle = '#2f422b';
  ctx.fillRect(p.x, p.y, p.w, p.h);
  ctx.fillStyle = '#79a244';
  ctx.fillRect(p.x, p.y - 8, p.w, 10);
  ctx.fillStyle = '#1d271b';
  for (let x = p.x + 16; x < p.x + p.w; x += 34) ctx.fillRect(x, p.y + 6, 14, 10);
}

function drawPalm(x, ground) {
  ctx.fillStyle = '#6b4424';
  ctx.fillRect(x, ground - 96, 18, 96);
  ctx.fillStyle = '#0c4b2d';
  for (let i = 0; i < 6; i++) {
    ctx.save();
    ctx.translate(x + 9, ground - 96);
    ctx.rotate((Math.PI * 2 * i) / 6);
    ctx.fillRect(0, -8, 74, 18);
    ctx.restore();
  }
}

function drawEntities() {
  bullets.forEach((b) => rect(b.x, b.y, b.w, b.h, '#fff067'));
  enemyBullets.forEach((b) => rect(b.x, b.y, b.w, b.h, '#ff603d'));
  enemies.forEach((e) => { if (e.alive) drawEnemy(e); });
  drawPlayer();
  particles.forEach((p) => rect(p.x, p.y, 5, 5, p.color));
}

function drawPlayer() {
  if (player.invuln > 0 && Math.floor(player.invuln * 18) % 2 === 0) return;
  const x = player.x;
  const y = player.y;
  const dir = player.facing;
  rect(x + 10, y, 14, 12, '#e7c79b');
  rect(x + 6, y + 12, 22, 25, '#55d06a');
  rect(x + (dir > 0 ? 22 : -12), y + 17, 22, 7, '#1f2430');
  rect(x + 9, y + 37, 8, 21, '#32406b');
  rect(x + 20, y + 37, 8, 21, '#32406b');
  rect(x + 5, y + 9, 25, 5, '#b83237');
  rect(x + (dir > 0 ? 32 : -18), y + 18, 18, 4, '#d6dad8');
}

function drawEnemy(e) {
  if (e.boss) {
    rect(e.x, e.y + 24, e.w, e.h - 24, '#50535a');
    rect(e.x + 14, e.y, e.w - 28, 42, '#798186');
    rect(e.x + 46, e.y + 48, 34, 34, '#e84838');
    rect(e.x - 18, e.y + 62, 28, 16, '#262b30');
    rect(e.x + e.w - 10, e.y + 62, 28, 16, '#262b30');
    return;
  }
  const body = e.type === 'turret' ? '#77756a' : e.type === 'runner' ? '#dd6b45' : '#c84f4f';
  rect(e.x + 8, e.y, e.w - 16, 12, '#e1b28e');
  rect(e.x + 5, e.y + 12, e.w - 10, 25, body);
  rect(e.x + 2, e.y + 18, 14, 7, '#252935');
  rect(e.x + 10, e.y + 37, 8, 12, '#1d2b33');
  rect(e.x + 23, e.y + 37, 8, 12, '#1d2b33');
}

function rect(x, y, w, h, color) {
  ctx.fillStyle = color;
  ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
}

function drawHud() {
  ctx.fillStyle = 'rgba(0, 0, 0, 0.52)';
  ctx.fillRect(18, 16, 360, 72);
  ctx.fillStyle = '#f4f7ef';
  ctx.font = '700 18px ui-monospace, SFMono-Regular, Menlo, monospace';
  ctx.fillText(`SCORE ${String(player.score).padStart(6, '0')}`, 32, 42);
  ctx.fillText(`LIVES ${Math.max(0, player.lives)}`, 232, 42);
  for (let i = 0; i < 5; i++) rect(32 + i * 28, 58, 20, 16, i < player.hp ? '#77ef7e' : '#39424a');
  const boss = enemies.find((e) => e.boss);
  if (boss && boss.alive && player.x > 3300) {
    ctx.fillStyle = 'rgba(0,0,0,0.58)';
    ctx.fillRect(610, 28, 290, 26);
    ctx.fillStyle = '#e84838';
    ctx.fillRect(620, 36, Math.max(0, 270 * boss.hp / 26), 10);
    ctx.fillStyle = '#fff';
    ctx.fillText('BUNKER CORE', 620, 78);
  }
}

function drawOverlay() {
  ctx.fillStyle = 'rgba(4, 9, 12, 0.78)';
  ctx.fillRect(0, 0, W, H);
  ctx.textAlign = 'center';
  ctx.fillStyle = won ? '#77ef7e' : '#ff6b40';
  ctx.font = '900 54px ui-sans-serif, system-ui';
  ctx.fillText(won ? 'MISSION CLEAR' : 'GAME OVER', W / 2, H / 2 - 18);
  ctx.fillStyle = '#f4f7ef';
  ctx.font = '700 20px ui-sans-serif, system-ui';
  ctx.fillText('按 R 重新开始', W / 2, H / 2 + 34);
  ctx.textAlign = 'left';
}

function loop(now) {
  const dt = Math.min(0.033, (now - last) / 1000);
  last = now;
  update(dt);
  draw();
  requestAnimationFrame(loop);
}

requestAnimationFrame(loop);
