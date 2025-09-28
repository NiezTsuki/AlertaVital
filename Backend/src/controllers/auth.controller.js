import { createUser, findUserByEmail, verifyPassword, issueToken, setLastLogin, getUserById } from '../services/user.service.js';

const ALLOWED_ROLES = ['ADULTO_MAYOR','CUIDADOR','ADMIN'];

export async function register(req, res) {
  try {
    const { rol, nombre_completo, correo, telefono, contrasena } = req.body || {};
    if (!ALLOWED_ROLES.includes(rol || '')) return res.status(400).json({ error: 'Rol inválido' });
    if (!nombre_completo || !correo || !contrasena) return res.status(400).json({ error: 'Faltan campos' });

    const existing = await findUserByEmail(correo);
    if (existing) return res.status(409).json({ error: 'Correo ya registrado' });

    const user = await createUser({ rol, nombre_completo, correo, telefono, contrasena });
    const token = issueToken(user);
    res.status(201).json({ user, token });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Error de servidor' });
  }
}

export async function login(req, res) {
  try {
    const { correo, contrasena } = req.body || {};
    if (!correo || !contrasena) return res.status(400).json({ error: 'Faltan credenciales' });

    const user = await findUserByEmail(correo);
    if (!user) return res.status(401).json({ error: 'Credenciales inválidas' });

    const ok = await verifyPassword(user.contrasena_hash, contrasena);
    if (!ok) return res.status(401).json({ error: 'Credenciales inválidas' });

    await setLastLogin(user.id);
    const token = issueToken(user);
    res.json({ token });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Error de servidor' });
  }
}

export async function me(req, res) {
  try {
    const user = await getUserById(req.user.sub);
    if (!user) return res.status(404).json({ error: 'No encontrado' });
    res.json({ user });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Error de servidor' });
  }
}
