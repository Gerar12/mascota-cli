#!/usr/bin/env python3
"""Dibuja a Clawd (el cangrejito de Claude Code) en pixel art como mascota Codex v2.

Genera una hoja de sprites de 8x11 celdas de 192x208 con las 9 animaciones estándar y las
16 direcciones de mirada, más pet.json. Uso: python3 scripts/dibujar-clawd.py [carpeta_destino]
(por defecto ~/.codex/pets/clawd, donde la leen Mascota y la app de ChatGPT/Codex).
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image

CELDA_W, CELDA_H = 192, 208
ESCALA = 7                      # un pixel de arte = 7x7 pixeles reales
GRID_W, GRID_H = 27, 29         # 189x203 pixeles
MARGEN_SUP = CELDA_H - GRID_H * ESCALA
MARGEN_IZQ = (CELDA_W - GRID_W * ESCALA) // 2

# Paleta
CONTORNO = (74, 38, 26, 255)
CUERPO = (217, 119, 87, 255)    # naranja de Claude
LUZ = (236, 152, 120, 255)
BRILLO = (246, 186, 160, 255)
BRILLO_OJO = (255, 255, 255, 255)
SOMBRA = (186, 94, 63, 255)
OJO = (30, 22, 20, 255)
CACHETE = (242, 148, 150, 255)
LAGRIMA = (110, 185, 255, 255)
PC_TAPA = (205, 208, 215, 255)
PC_BORDE = (142, 146, 156, 255)
PC_LOGO = (245, 245, 250, 255)
GLOBO = (252, 252, 252, 255)

ANCHO, ALTO = 18, 12            # cuerpo
BX, BY = (GRID_W - ANCHO) // 2, 13


class Lienzo:
    def __init__(self):
        self.px = {}

    def punto(self, x, y, color):
        if 0 <= x < GRID_W and 0 <= y < GRID_H:
            self.px[(x, y)] = color

    def rect(self, x, y, w, h, color):
        for i in range(w):
            for j in range(h):
                self.punto(x + i, y + j, color)

    def contorno(self):
        vecinos = ((1, 0), (-1, 0), (0, 1), (0, -1))
        borde = {(x + dx, y + dy) for (x, y) in self.px for dx, dy in vecinos} - set(self.px)
        for x, y in borde:
            self.punto(x, y, CONTORNO)

    def espejo(self):
        self.px = {(GRID_W - 1 - x, y): c for (x, y), c in self.px.items()}


def cuerpo(l, bx, by, aplastar=0):
    """Cuerpo con esquinas de arriba redondeadas, luz arriba y sombra abajo. aplastar: mas ancho y bajo."""
    x, y, w, h = bx - aplastar, by + aplastar, ANCHO + 2 * aplastar, ALTO - aplastar
    l.rect(x, y, w, h, CUERPO)
    l.rect(x + 1, y, w - 2, 1, LUZ)
    l.rect(x, y + h - 1, w, 1, SOMBRA)
    l.rect(x + w - 1, y + 1, 1, h - 1, SOMBRA)          # volumen: lado derecho en sombra
    l.rect(x + 2, y + 1, 3, 1, BRILLO)                  # brillo arriba a la izquierda
    l.punto(x + 1, y + 2, BRILLO)
    for cx in (x, x + w - 1):
        l.px.pop((cx, y), None)
    return x, y, w, h


def patas(l, bx, by, levantar=None):
    """Cuatro patitas de 2x3. levantar: 'a' o 'b' sube un par (caminar)."""
    for i, px in enumerate((bx + 1, bx + 5, bx + ANCHO - 7, bx + ANCHO - 3)):
        par = 'a' if i % 2 == 0 else 'b'
        alto = 2 if levantar == par else 3
        l.rect(px, by + ALTO, 2, alto, SOMBRA)


def brazo(l, lado, pose, bx, by, extra=0):
    """lado: 'i' o 'd'. Poses: lado, arriba, diagonal, caido, teclear, barbilla."""
    fuera = bx - 3 if lado == 'i' else bx + ANCHO
    pegado = bx - 2 if lado == 'i' else bx + ANCHO
    if pose == 'lado':
        l.rect(fuera, by + 5 + extra, 3, 3, CUERPO)
        l.rect(fuera, by + 7 + extra, 3, 1, SOMBRA)
    elif pose == 'arriba':
        l.rect(pegado, by - 3, 2, 7, CUERPO)
    elif pose == 'diagonal':
        paso = -1 if lado == 'i' else 1
        base = bx - 2 if lado == 'i' else bx + ANCHO
        for k in range(4):
            l.rect(base + paso * k, by + 3 - k, 2, 2, CUERPO)
    elif pose == 'caido':
        l.rect(pegado, by + 7, 2, 4, CUERPO)
    elif pose == 'teclear':
        x = bx + 2 if lado == 'i' else bx + ANCHO - 5
        y = by + 9 + extra                   # manitas sobre el borde de la laptop, con contorno propio
        l.rect(x - 1, y - 1, 5, 4, CONTORNO)
        l.rect(x, y, 3, 2, CUERPO)
    elif pose == 'barbilla':
        l.rect(pegado, by + 4, 2, 6, CUERPO)
        l.rect(pegado - 1, by + 4, 1, 2, CUERPO)


def ojos(l, bx, by, tipo='abiertos', dx=0, dy=0):
    for ox in (bx + 4, bx + ANCHO - 6):
        x, y = ox + dx, by + 3 + dy
        if tipo == 'abiertos':
            l.rect(x, y, 2, 3, OJO)
            l.punto(x, y, BRILLO_OJO)
        elif tipo == 'cerrados':
            l.rect(x, y + 2, 2, 1, OJO)
        elif tipo == 'felices':        # ^ ^
            l.punto(x - 1, y + 2, OJO)
            l.rect(x, y + 1, 2, 1, OJO)
            l.punto(x + 2, y + 2, OJO)
        elif tipo == 'tristes':        # cejas caidas hacia afuera
            l.rect(x, y + 2, 2, 1, OJO)
            l.punto(x + (-1 if ox == bx + 4 else 2), y + 3, OJO)
        elif tipo == 'entrecerrados':
            l.rect(x, y + 1, 2, 2, OJO)
            l.rect(x - 1, y, 4, 1, SOMBRA)


def cachetes(l, bx, by):
    l.rect(bx + 2, by + 7, 2, 1, CACHETE)
    l.rect(bx + ANCHO - 4, by + 7, 2, 1, CACHETE)


def laptop(l, bx, by):
    l.rect(bx + 2, by + 8, ANCHO - 4, ALTO - 5, PC_TAPA)
    l.rect(bx + 2, by + 8, ANCHO - 4, 1, PC_BORDE)
    l.rect(bx + 1, by + ALTO + 3, ANCHO - 2, 1, PC_BORDE)
    l.rect(bx + ANCHO // 2 - 1, by + 11, 2, 2, PC_LOGO)


def globo_pregunta(l, bx, by):
    """Globo blanco con ? pegado a la cabeza (arriba a la derecha)."""
    x, y = bx + 1, by - 11
    l.rect(x, y, 9, 9, GLOBO)
    for cx, cy in ((x, y), (x + 8, y), (x, y + 8), (x + 8, y + 8)):
        l.px.pop((cx, cy), None)
    l.rect(x + 5, y + 9, 2, 2, GLOBO)        # colita que toca la cabeza
    for fila, patron in enumerate((".###.", "#...#", "...#.", "..#..", ".....", "..#..")):
        for col, c in enumerate(patron):
            if c == '#':
                l.punto(x + 2 + col, y + 1 + fila, SOMBRA)


def mascota(dy=0, dx=0, aplastar=0, bi='lado', bd='lado', ei=0, ed=0, levantar=None,
            ojos_tipo='abiertos', mirar=(0, 0), rubor=None, lagrima=0, extras=()):
    l = Lienzo()
    bx, by = BX + dx, BY + dy
    patas(l, bx, by, levantar)
    x, y, w, h = cuerpo(l, bx, by, aplastar)
    if 'laptop' in extras:
        laptop(l, bx, by)                    # las patitas que teclean van encima
    brazo(l, 'i', bi, bx, y, ei)
    brazo(l, 'd', bd, bx, y, ed)
    ojos(l, bx, y, ojos_tipo, *mirar)
    if rubor if rubor is not None else ojos_tipo != 'tristes':
        cachetes(l, bx, y)
    if lagrima:
        l.rect(bx + 4, y + 6, 2, lagrima, LAGRIMA)
    if 'pregunta' in extras:
        globo_pregunta(l, bx, y)
    l.contorno()
    return l


def filas():
    idle = [
        mascota(),
        mascota(),
        mascota(aplastar=1),
        mascota(aplastar=1, ojos_tipo='cerrados'),
        mascota(),
        mascota(mirar=(1, 0)),
    ]
    caminar = []
    for f in range(8):
        lev = 'a' if f % 4 < 2 else 'b'
        caminar.append(mascota(dy=-(f % 2), levantar=lev, mirar=(1, 0),
                               ei=1 if lev == 'a' else -1, ed=-1 if lev == 'a' else 1))
    caminar_izq = []
    for c in caminar:
        m = Lienzo()
        m.px = dict(c.px)
        m.espejo()
        caminar_izq.append(m)
    saludar = [mascota(bd=p, ojos_tipo='felices', rubor=True) for p in ('lado', 'diagonal', 'arriba', 'diagonal')]
    saltar = [
        mascota(aplastar=2, bi='caido', bd='caido'),
        mascota(dy=-3, bi='arriba', bd='arriba'),
        mascota(dy=-6, bi='arriba', bd='arriba', ojos_tipo='felices', rubor=True),
        mascota(dy=-2, bi='diagonal', bd='diagonal', ojos_tipo='felices'),
        mascota(aplastar=1, ojos_tipo='felices', rubor=True),
    ]
    fallar = []
    for f in range(8):
        fallar.append(mascota(dx=(-1, 1, -1, 0, 0, 0, 0, 0)[f], aplastar=1 if f >= 2 else 0,
                              bi='caido', bd='caido', ojos_tipo='tristes', lagrima=min(f // 2, 3)))
    esperar = []
    for f in range(6):
        esperar.append(mascota(dy=(0, -1, -1, 0, 0, 0)[f], bd='arriba' if f in (1, 2, 3) else 'diagonal',
                               mirar=(1, -1), extras=('pregunta',)))
    trabajar = []
    for f in range(6):
        trabajar.append(mascota(bi='teclear', bd='teclear', ei=-(f % 2), ed=-((f + 1) % 2),
                                mirar=((0, 1, 0, -1, 0, 1)[f] * 0, 1), extras=('laptop',),
                                ojos_tipo='cerrados' if f == 4 else 'abiertos'))
    revisar = []
    for f in range(6):
        revisar.append(mascota(bd='barbilla', ojos_tipo='cerrados' if f == 3 else 'entrecerrados',
                               mirar=((0, -1, -1, 0, 1, 1)[f], 0)))
    mirar = []
    for k in range(16):
        a = math.radians(k * 22.5)
        sx, sy = math.sin(a), -math.cos(a)
        mirar.append(mascota(dx=round(sx), dy=round(sy * 0.6), mirar=(round(sx * 1.4), round(sy * 1.4))))
    return [idle, caminar, caminar_izq, saludar, saltar, fallar, esperar, trabajar, revisar, mirar[:8], mirar[8:]]


def pintar(hoja, lienzo, col, fila):
    ox, oy = col * CELDA_W + MARGEN_IZQ, fila * CELDA_H + MARGEN_SUP
    for (x, y), c in lienzo.px.items():
        for i in range(ESCALA):
            for j in range(ESCALA):
                hoja.putpixel((ox + x * ESCALA + i, oy + y * ESCALA + j), c)


def main():
    destino = Path(sys.argv[1] if len(sys.argv) > 1 else "~/.codex/pets/clawd").expanduser()
    destino.mkdir(parents=True, exist_ok=True)
    hoja = Image.new("RGBA", (CELDA_W * 8, CELDA_H * 11), (0, 0, 0, 0))
    for f, cuadros in enumerate(filas()):
        for c, lienzo in enumerate(cuadros):
            pintar(hoja, lienzo, c, f)
    hoja.save(destino / "spritesheet.png")
    (destino / "pet.json").write_text(json.dumps({
        "id": "clawd",
        "displayName": "Clawd",
        "description": "El cangrejito de Claude Code, en pixel art.",
        "spriteVersionNumber": 2,
        "spritesheetPath": "spritesheet.png",
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"Clawd listo en {destino}")


if __name__ == "__main__":
    main()
