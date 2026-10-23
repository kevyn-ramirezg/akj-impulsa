// Ejecuta las pruebas en una base PostgreSQL local (PGlite) y guarda la evidencia.
// Uso: npm install @electric-sql/pglite  &&  node ejecutar_pruebas_local.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, writeFileSync } from 'node:fs';

const leer = f => readFileSync(new URL(f, import.meta.url), 'utf8');
const db = new PGlite();
const inicio = new Date();
for (const f of ['00_simulacion_auth_local.sql', '01_esquema_y_permisos.sql', '02_datos_de_prueba.sql']) await db.exec(leer(f));
const res = await db.exec(leer('03_pruebas_permisos.sql'));
const filas = res.at(-1).rows;
const version = (await db.query('select version()')).rows[0].version;

const casos = filas.filter(f => f.caso !== 'TOTAL');
const total = filas.find(f => f.caso === 'TOTAL');
console.table(casos);
console.log(total.quien);

const csv = [['caso', 'quien', 'operacion', 'esperado', 'obtenido', 'cumple']]
  .concat(casos.map(f => [f.caso, f.quien, f.operacion, f.esperado, f.obtenido, f.cumple]))
  .map(r => r.map(v => `"${String(v).replaceAll('"', '""')}"`).join(',')).join('\n');
writeFileSync(new URL('resultados_pruebas_local.csv', import.meta.url), '﻿' + csv);
writeFileSync(new URL('registro_ejecucion_local.txt', import.meta.url),
  `AKJ Impulsa · Ejecución local de pruebas de permisos\n` +
  `Fecha: ${inicio.toISOString()}\nMotor: ${version}\nNode: ${process.version}\n` +
  `Archivos: 00_simulacion_auth_local.sql, 01_esquema_y_permisos.sql, 02_datos_de_prueba.sql, 03_pruebas_permisos.sql\n` +
  `Resultado: ${total.quien}\n\n` +
  casos.map(f => `${f.caso.padEnd(4)} ${f.cumple === 'Sí' ? 'CUMPLE' : 'FALLA '}  ${f.quien} · ${f.operacion} · esperado ${f.esperado} · obtenido ${f.obtenido}`).join('\n') + '\n');
process.exit(casos.every(f => f.cumple === 'Sí') ? 0 : 1);
