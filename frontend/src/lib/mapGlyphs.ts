// Canvas glyph drawing for the machines map, kept DOM-free (a 2d context goes in, pixels come out)
// so the shapes can be rendered and inspected in isolation.
export const EDGE_MESH_COLOR = '#4E8241'

/** Thunderbolt-plug glyph (plug outline + bolt + contact dots) for mesh edges. */
export function drawPlugGlyph(ctx: CanvasRenderingContext2D, x: number, y: number, scale: number, color: string): void {
  ctx.save()
  ctx.translate(x, y)
  ctx.scale(scale, scale)
  ctx.strokeStyle = color
  ctx.fillStyle = color
  ctx.lineWidth = 1.4
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  // plug body: rounded oval cable-end
  ctx.beginPath()
  ctx.roundRect(-5, -5.5, 10, 11, 4.5)
  ctx.stroke()
  // two contact dots
  ctx.beginPath()
  ctx.arc(-2, 3.2, 0.8, 0, Math.PI * 2)
  ctx.arc(2, 3.2, 0.8, 0, Math.PI * 2)
  ctx.fill()
  // lightning bolt
  ctx.beginPath()
  ctx.moveTo(0.8, -3.6)
  ctx.lineTo(-2.2, 0.4)
  ctx.lineTo(-0.2, 0.4)
  ctx.lineTo(-0.8, 1.2)
  ctx.moveTo(-0.8, 1.2)
  ctx.lineTo(0.2, 1.2)
  ctx.stroke()
  ctx.restore()
}
