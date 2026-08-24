/**
 * Carga la contraseña del certificado .p12 en `empresa_sifen_config`, cifrada
 * con el mismo algoritmo que usa la app (`src/lib/sifen/security.ts`).
 *
 * Vía de escape al formulario web: escribe directo contra Postgres. Útil cuando
 * la pantalla de configuración guarda "con éxito" pero deja la columna en NULL.
 *
 * La contraseña se toma de una variable de entorno y NUNCA se imprime.
 *
 * Uso (PowerShell):
 *   $env:SUPABASE_DB_URL="postgresql://..."
 *   $env:SIFEN_SECRETS_KEY="<la misma clave que tiene el servidor>"
 *   $env:P12_PASSWORD="<contraseña del certificado>"
 *   node scripts/cargar-sifen-certificado-password.mjs
 *
 * Uso (bash):
 *   SUPABASE_DB_URL="postgresql://..." \
 *   SIFEN_SECRETS_KEY="..." \
 *   P12_PASSWORD="..." \
 *   node scripts/cargar-sifen-certificado-password.mjs
 *
 * Opcional: --schema <nombre>  (por defecto `hhperfomance`)
 *           --dry-run          (cifra y verifica, pero no escribe)
 */
import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from "node:crypto";
import pg from "pg";

// Debe coincidir EXACTAMENTE con src/lib/sifen/security.ts. Si algo de esto
// cambia allá, la app no podrá descifrar lo que escriba este script.
const KDF_SALT = "neura-sifen-kdf-v1";
const SCRYPT_PARAMS = { N: 16384, r: 8, p: 1 };
const ALGO = "aes-256-gcm";
const IV_LEN = 16;
const PREFIX = "neura:v1:";

function deriveKey(raw) {
  return scryptSync(raw, KDF_SALT, 32, SCRYPT_PARAMS);
}

function encryptSecret(plaintext, keyRaw) {
  const key = deriveKey(keyRaw);
  const iv = randomBytes(IV_LEN);
  const cipher = createCipheriv(ALGO, key, iv);
  const enc = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${PREFIX}${iv.toString("base64")}:${tag.toString("base64")}:${enc.toString("base64")}`;
}

function decryptSecret(stored, keyRaw) {
  if (!stored.startsWith(PREFIX)) throw new Error("Formato de secreto no reconocido");
  const [ivB64, tagB64, dataB64] = stored.slice(PREFIX.length).split(":");
  const decipher = createDecipheriv(ALGO, deriveKey(keyRaw), Buffer.from(ivB64, "base64"));
  decipher.setAuthTag(Buffer.from(tagB64, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(dataB64, "base64")),
    decipher.final(),
  ]).toString("utf8");
}

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

async function main() {
  const dbUrl = process.env.SUPABASE_DB_URL?.trim() || process.env.DATABASE_URL?.trim();
  const key = process.env.SIFEN_SECRETS_KEY?.trim();
  const password = process.env.P12_PASSWORD;
  const schema = arg("--schema", "hhperfomance");
  const dryRun = process.argv.includes("--dry-run");

  const faltan = [];
  if (!dbUrl) faltan.push("SUPABASE_DB_URL");
  if (!key) faltan.push("SIFEN_SECRETS_KEY");
  if (!password) faltan.push("P12_PASSWORD");
  if (faltan.length) {
    console.error(`Faltan variables de entorno: ${faltan.join(", ")}`);
    process.exit(1);
  }
  if (key.length < 16) {
    console.error("SIFEN_SECRETS_KEY debe tener al menos 16 caracteres (la app exige lo mismo).");
    process.exit(1);
  }

  // Cifrar y verificar el round-trip ANTES de tocar la base.
  const cipherText = encryptSecret(password, key);
  if (decryptSecret(cipherText, key) !== password) {
    console.error("El descifrado de verificación no coincide. No se escribió nada.");
    process.exit(1);
  }
  console.log(`Cifrado OK · formato ${PREFIX}… · ${cipherText.length} chars`);

  const client = new pg.Client({ connectionString: dbUrl });
  await client.connect();
  try {
    const t = `"${schema.replace(/"/g, '""')}"."empresa_sifen_config"`;
    const { rows } = await client.query(
      `SELECT empresa_id, ruc, certificado_path FROM ${t} LIMIT 2`
    );
    if (rows.length === 0) throw new Error(`No hay configuración SIFEN en ${schema}.`);
    if (rows.length > 1) throw new Error("Hay más de una configuración; revisar manualmente.");

    const cfg = rows[0];
    console.log(`Empresa   : ${cfg.empresa_id}`);
    console.log(`RUC       : ${cfg.ruc}`);
    console.log(`.p12      : ${cfg.certificado_path ?? "(sin certificado cargado)"}`);
    if (!cfg.certificado_path) {
      console.warn("Aviso: no hay .p12 cargado. La contraseña sola no alcanza para firmar.");
    }

    if (dryRun) {
      console.log("\n--dry-run: no se escribió nada.");
      return;
    }

    await client.query(
      `UPDATE ${t} SET certificado_password_encrypted = $1 WHERE empresa_id = $2`,
      [cipherText, cfg.empresa_id]
    );

    // Releer de la base y descifrar, para confirmar que quedó utilizable.
    const { rows: after } = await client.query(
      `SELECT certificado_password_encrypted p FROM ${t} WHERE empresa_id = $1`,
      [cfg.empresa_id]
    );
    const ok = decryptSecret(after[0].p, key) === password;
    console.log(`\nGuardado  : ${after[0].p.slice(0, 9)}… (${after[0].p.length} chars)`);
    console.log(`Verificado: ${ok ? "OK — descifra correctamente desde la base" : "FALLÓ"}`);
    if (!ok) process.exit(1);
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error("Error:", e.message);
  process.exit(1);
});
