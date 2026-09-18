import { Controller } from "@hotwired/stimulus"

// A slowly growing evidence graph behind the landing page. Nodes attach to
// existing nodes, links form and occasionally cross-link, audit pulses travel
// along links, and old leaves fade so the graph keeps evolving. Decorative
// only: nothing here reads ledger data, and reduced-motion users get one
// static frame.
export default class extends Controller {
  static values = { maxNodes: { type: Number, default: 130 }, opacity: { type: Number, default: 0.55 } }

  connect() {
    this.ctx = this.element.getContext("2d")
    this.nodes = []
    this.links = []
    this.pulses = []
    this.blocks = []
    this.nextBirth = 0
    this.nextPulse = 0
    this.nextDeath = 0
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.onResize = () => this.resize()
    this.onVisibility = () => (document.hidden ? this.stop() : this.start())
    window.addEventListener("resize", this.onResize)
    document.addEventListener("visibilitychange", this.onVisibility)
    this.resize()
    this.seed()
    // Open on a graph already half grown, the newest nodes still fading in,
    // then keep growing from there.
    if (this.reduced) {
      for (let i = 0; i < 16; i++) this.grow(-6000)
      this.draw(performance.now())
    } else {
      for (let i = 0; i < 12; i++) this.grow(-6000 + i * 450)
      this.start()
    }
  }

  disconnect() {
    this.stop()
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  start() {
    if (this.frame || this.reduced) return
    this.last = performance.now()
    const tick = (now) => {
      this.step(now, Math.min(now - this.last, 100))
      this.last = now
      this.draw(now)
      this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }

  stop() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
  }

  resize() {
    const dpr = window.devicePixelRatio || 1
    this.width = window.innerWidth
    this.height = window.innerHeight
    this.element.width = this.width * dpr
    this.element.height = this.height * dpr
    this.element.style.width = `${this.width}px`
    this.element.style.height = `${this.height}px`
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  }

  seed() {
    const now = performance.now()
    for (let i = 0; i < 6; i++) {
      this.addNode(this.width * (0.1 + 0.8 * Math.random()), this.height * (0.1 + 0.8 * Math.random()), now - 5000, null, "claim")
    }
  }

  addNode(x, y, born, parent, kind) {
    const node = {
      x, y, ax: x, ay: y, born, dead: null,
      r: kind === "claim" ? 3.5 : 2 + Math.random() * 1.5,
      phase: Math.random() * Math.PI * 2,
      drift: 0.15 + Math.random() * 0.25,
      degree: 0,
      kind
    }
    this.nodes.push(node)
    if (parent) this.addLink(parent, node, born)
    return node
  }

  addLink(a, b, born) {
    if (a === b || this.links.some((l) => (l.a === a && l.b === b) || (l.a === b && l.b === a))) return
    this.links.push({ a, b, born, dead: null })
    a.degree++
    b.degree++
  }

  // Grow a branch: a statement node attaches to an existing low-degree node,
  // then forks into two to four parts, its decomposition. Live growth opens
  // with a small block of text that breaks into lines; each line flies to its
  // place and shrinks into a dot. Seeded growth (offset < 0) skips the block.
  grow(offset = 0) {
    const alive = this.nodes.filter((n) => !n.dead)
    if (alive.length === 0 || alive.length >= this.maxNodesValue) return
    const now = performance.now()
    const born = now + offset
    const live = offset >= 0
    const pool = alive.slice().sort((p, q) => p.degree - q.degree)
    const parent = pool[Math.floor(Math.random() * Math.min(pool.length, 12))]
    const heading = this.outward(parent)
    const statement = this.addNode(...this.place(parent, heading, 70 + Math.random() * 50), live ? born + 3400 : born, parent, "claim")
    const forks = 2 + Math.floor(Math.random() * 3)
    const spread = Math.PI * 0.7
    const parts = []
    for (let i = 0; i < forks; i++) {
      const angle = heading - spread / 2 + (spread * (i + 0.5)) / forks + (Math.random() - 0.5) * 0.3
      const partBorn = live ? born + 3700 + i * 200 : born + 500 + i * 350
      const part = this.addNode(...this.place(statement, angle, 45 + Math.random() * 40), partBorn, statement, "evidence")
      parts.push(part)
      if (Math.random() < 0.2) {
        const near = alive
          .filter((n) => n !== parent && Math.hypot(n.x - part.x, n.y - part.y) < 140)
          .sort((p, q) => p.degree - q.degree)[0]
        if (near) this.addLink(near, part, part.born + 600)
      }
    }
    if (live) this.blocks.push(this.block(statement, parts, born))
  }

  // A paragraph glyph: one line per node, the first (widest) for the statement.
  block(statement, parts, start) {
    const pieces = [statement, ...parts].map((node, i) => ({
      node,
      w: i === 0 ? 58 : 30 + Math.random() * 24,
      jx: (Math.random() - 0.5) * 18,
      jy: (Math.random() - 0.5) * 12,
      depart: 2300 + i * 200,
      travel: 1200
    }))
    return { x: statement.ax, y: statement.ay, start, pieces, lineGap: 7.5, width: 66 }
  }

  // Direction away from the node's neighbours, so branches reach into open space.
  outward(node) {
    const neighbours = this.links.filter((l) => !l.dead && (l.a === node || l.b === node)).map((l) => (l.a === node ? l.b : l.a))
    if (neighbours.length === 0) return Math.random() * Math.PI * 2
    const sx = neighbours.reduce((acc, n) => acc + (n.x - node.x), 0)
    const sy = neighbours.reduce((acc, n) => acc + (n.y - node.y), 0)
    return Math.atan2(-sy, -sx) + (Math.random() - 0.5) * 0.8
  }

  place(from, angle, dist) {
    const margin = 70
    return [
      Math.min(this.width - margin, Math.max(margin, from.x + Math.cos(angle) * dist)),
      Math.min(this.height - margin, Math.max(margin, from.y + Math.sin(angle) * dist))
    ]
  }

  // Retire an old leaf and its links so the graph keeps evolving at the cap.
  retire() {
    const now = performance.now()
    const leaves = this.nodes.filter((n) => !n.dead && n.degree <= 1 && now - n.born > 20000)
    if (leaves.length === 0) return
    const node = leaves[Math.floor(Math.random() * leaves.length)]
    node.dead = now
    this.links.forEach((l) => {
      if (!l.dead && (l.a === node || l.b === node)) {
        l.dead = now
        l.a.degree--
        l.b.degree--
      }
    })
  }

  pulse() {
    const live = this.links.filter((l) => !l.dead)
    if (live.length === 0) return
    const link = live[Math.floor(Math.random() * live.length)]
    this.pulses.push({ link, start: performance.now(), duration: 1800 + Math.random() * 1200, reverse: Math.random() < 0.5 })
  }

  step(now, dt) {
    if (now > this.nextBirth) {
      this.grow()
      this.nextBirth = now + 1800 + Math.random() * 2200
    }
    if (now > this.nextPulse) {
      this.pulse()
      this.nextPulse = now + 900 + Math.random() * 1600
    }
    const alive = this.nodes.filter((n) => !n.dead).length
    if (alive >= this.maxNodesValue * 0.85 && now > this.nextDeath) {
      this.retire()
      this.nextDeath = now + 1500 + Math.random() * 2500
    }
    const t = now / 1000
    this.nodes.forEach((n) => {
      n.x = n.ax + Math.sin(t * n.drift + n.phase) * 6
      n.y = n.ay + Math.cos(t * n.drift * 0.8 + n.phase) * 6
    })
    const cutoff = now - 6000
    this.nodes = this.nodes.filter((n) => !n.dead || n.dead > cutoff)
    this.links = this.links.filter((l) => !l.dead || l.dead > cutoff)
    this.pulses = this.pulses.filter((p) => now - p.start < p.duration && !p.link.dead)
    this.blocks = this.blocks.filter((b) => now - b.start < 6000)
    void dt
  }

  alpha(item, now) {
    const fadeIn = Math.min(1, (now - item.born) / 2500)
    const fadeOut = item.dead ? Math.max(0, 1 - (now - item.dead) / 4000) : 1
    return Math.max(0, fadeIn * fadeOut)
  }

  draw(now) {
    const ctx = this.ctx
    const base = this.opacityValue
    ctx.clearRect(0, 0, this.width, this.height)
    ctx.lineWidth = 1
    this.links.forEach((l) => {
      const a = this.alpha(l, now)
      if (a <= 0) return
      ctx.strokeStyle = `rgba(44, 90, 134, ${0.35 * a * base})`
      ctx.beginPath()
      ctx.moveTo(l.a.x, l.a.y)
      ctx.lineTo(l.b.x, l.b.y)
      ctx.stroke()
    })
    this.blocks.forEach((b) => this.drawBlock(b, now))
    this.nodes.forEach((n) => {
      const a = this.alpha(n, now)
      if (a <= 0) return
      ctx.beginPath()
      ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2)
      ctx.fillStyle = n.kind === "claim" ? `rgba(44, 90, 134, ${0.9 * a * base})` : `rgba(255, 253, 249, ${a})`
      ctx.fill()
      ctx.strokeStyle = `rgba(44, 90, 134, ${0.8 * a * base})`
      ctx.stroke()
    })
    this.pulses.forEach((p) => {
      let f = (now - p.start) / p.duration
      if (p.reverse) f = 1 - f
      const x = p.link.a.x + (p.link.b.x - p.link.a.x) * f
      const y = p.link.a.y + (p.link.b.y - p.link.a.y) * f
      const glow = Math.sin(Math.min(1, (now - p.start) / p.duration) * Math.PI)
      ctx.beginPath()
      ctx.arc(x, y, 2.2, 0, Math.PI * 2)
      ctx.fillStyle = `rgba(44, 90, 134, ${0.9 * glow * base})`
      ctx.fill()
    })
  }

  // Phases: the page fades in and holds (0 to 1600ms), the lines jitter apart
  // as the page dissolves (1600 to 2300ms), then each line flies to its node
  // and shrinks into it.
  drawBlock(b, now) {
    const ctx = this.ctx
    const base = this.opacityValue
    const t = now - b.start
    if (t < 0) return
    const ease = (v) => (v < 0.5 ? 2 * v * v : 1 - Math.pow(-2 * v + 2, 2) / 2)
    const height = b.pieces.length * b.lineGap + 8
    const left = b.x - b.width / 2
    const top = b.y - height / 2
    const pageAlpha = t < 700 ? t / 700 : t < 1600 ? 1 : Math.max(0, 1 - (t - 1600) / 700)
    if (pageAlpha > 0) {
      ctx.fillStyle = `rgba(255, 253, 249, ${0.92 * pageAlpha})`
      ctx.strokeStyle = `rgba(44, 90, 134, ${0.7 * pageAlpha})`
      ctx.beginPath()
      if (ctx.roundRect) ctx.roundRect(left - 6, top - 4, b.width + 12, height + 8, 3)
      else ctx.rect(left - 6, top - 4, b.width + 12, height + 8)
      ctx.fill()
      ctx.stroke()
    }
    b.pieces.forEach((piece, i) => {
      const lineY = top + 4 + i * b.lineGap + 2
      const appear = Math.min(1, Math.max(0, (t - 200 - i * 140) / 500))
      if (appear <= 0) return
      const scatter = Math.min(1, Math.max(0, (t - 1600) / 700))
      const flight = Math.min(1, Math.max(0, (t - piece.depart) / piece.travel))
      if (flight >= 1) return
      const f = ease(flight)
      const sx = left + 3 + piece.jx * scatter
      const sy = lineY + piece.jy * scatter
      const size = piece.node.r * 2
      const w = piece.w + (size - piece.w) * f
      const h = 3.4 + (size - 3.4) * f
      const x = sx + (piece.node.ax - w / 2 - sx) * f
      const y = sy + (piece.node.ay - sy) * f
      const alpha = appear * (flight > 0.8 ? 1 - (flight - 0.8) / 0.2 : 1)
      ctx.fillStyle = `rgba(44, 90, 134, ${0.75 * alpha})`
      ctx.beginPath()
      if (ctx.roundRect) ctx.roundRect(x, y - h / 2, w, h, h / 2)
      else ctx.rect(x, y - h / 2, w, h)
      ctx.fill()
    })
  }
}
