import { createUser, findUserByEmail, verifyPassword, issueToken, setLastLogin, getUserById } from '../services/user.service.js';

const ALLOWED_ROLES = ['ADULTO_MAYOR', 'CUIDADOR'];

export async function register(req, res) {
  try {
    const { rol, nombre_completo, correo, telefono, contrasena } = req.body || {};

    //validaciones
    if (!rol || !ALLOWED_ROLES.includes(rol)) {
      return res.status(400).json({ error: 'El rol proporcionado es inválido. Debe ser ADULTO_MAYOR o CUIDADOR.' });
    }
    if (!nombre_completo || nombre_completo.trim() === '') {
      return res.status(400).json({ error: 'El nombre completo es requerido.' });
    }
    if (!correo || !correo.includes('@')) {
      return res.status(400).json({ error: 'Se requiere un correo electrónico válido.' });
    }
    if (!contrasena || contrasena.length < 6) {
      return res.status(400).json({ error: 'La contraseña es requerida y debe tener al menos 6 caracteres.' });
    }

    const existing = await findUserByEmail(correo);
    if (existing) {
      return res.status(409).json({ error: 'El correo electrónico ya está registrado.' });
    }

    const user = await createUser({ rol, nombre_completo, correo, telefono, contrasena });
    const token = issueToken(user);
    res.status(201).json({ user, token });

  } catch (e) {
    console.error('[REGISTER_ERROR]', e);
    res.status(500).json({ error: 'Ocurrió un error en el servidor al intentar registrar el usuario.' });
  }
}

export async function login(req, res) {
  try {
    const { correo, contrasena } = req.body || {};

    if (!correo) {
      return res.status(400).json({ error: 'El correo electrónico es requerido.' });
    }
    if (!contrasena) {
      return res.status(400).json({ error: 'La contraseña es requerida.' });
    }

    const user = await findUserByEmail(correo);
    
    if (!user) {
      return res.status(401).json({ error: 'Credenciales inválidas.' });
    }

    const passwordIsValid = await verifyPassword(user.contrasena_hash, contrasena);
    if (!passwordIsValid) {
      return res.status(401).json({ error: 'Credenciales inválidas.' });
    }

    await setLastLogin(user.id);
    const token = issueToken(user);
    res.json({ token });

  } catch (e) {
    console.error('[LOGIN_ERROR]', e);
    res.status(500).json({ error: 'Ocurrió un error en el servidor durante el inicio de sesión.' });
  }
}

export async function me(req, res) {
  try {
    
    const user = await getUserById(req.user.sub);
    if (!user) {
      return res.status(404).json({ error: 'Usuario no encontrado.' });
    }
    res.json({ user });
  } catch (e) {
    console.error('[ME_ERROR]', e);
    res.status(500).json({ error: 'Ocurrió un error al obtener los datos del usuario.' });
  }
}