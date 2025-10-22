import jwt from 'jsonwebtoken';
import { Resend } from 'resend';
import { 
  createUser, 
  findUserByEmail, 
  verifyPassword, 
  issueToken, 
  setLastLogin, 
  getUserById,
  setCorreoVerificado ,
  updatePassword
} from '../services/user.service.js';
import { config } from '../config/env.js';

// Asegúrate de tener RESEND_API_KEY y FRONTEND_URL 
const resend = new Resend(config.resendApiKey);

const ALLOWED_ROLES = ['ADULTO_MAYOR', 'CUIDADOR'];

export async function register(req, res) {
  try {
    const { rol, nombre_completo, correo, telefono, contrasena } = req.body || {};

    // Validaciones (sin cambios)
    if (!rol || !ALLOWED_ROLES.includes(rol)) return res.status(400).json({ error: 'El rol proporcionado es inválido.' });
    if (!nombre_completo || nombre_completo.trim() === '') return res.status(400).json({ error: 'El nombre completo es requerido.' });
    if (!correo || !correo.includes('@')) return res.status(400).json({ error: 'Se requiere un correo electrónico válido.' });
    if (!contrasena || contrasena.length < 6) return res.status(400).json({ error: 'La contraseña debe tener al menos 6 caracteres.' });

    const existing = await findUserByEmail(correo);
    if (existing) return res.status(409).json({ error: 'El correo electrónico ya está registrado.' });

    //Crea el usuario
    const user = await createUser({ rol, nombre_completo, correo, telefono, contrasena });

    // GENERA UN TOKEN DE VERIFICACIÓN
    const verificationToken = jwt.sign(
      { userId: user.id, type: 'EMAIL_VERIFICATION' },
      config.jwtSecret,
      { expiresIn: '1h' } // El enlace es válido por 1 hora
    );

    // Debes tener una variable FRONTEND_URL 
const verificationUrl = `${config.frontendUrl}?token=${verificationToken}`;

   await resend.emails.send({
      from: 'AlertaVital <noreply@alertavital.xyz>',
      to: [user.correo],
      subject: 'Verifica tu cuenta en AlertaVital',
      html: `
        <!DOCTYPE html>
        <html lang="es">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { margin: 0; padding: 0; background-color: #f2f0f9; /* Color lavanda muy claro de fondo */ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
            .container { max-width: 600px; margin: 40px auto; background-color: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.05); border-top: 5px solid #6A5ACD; /* Borde superior morado */ }
            .content { padding: 40px; text-align: center; color: #333333; }
            .logo { max-width: 130px; margin: 0 auto 30px auto; }
            h1 { font-size: 24px; margin-bottom: 15px; }
            p { margin-bottom: 25px; font-size: 16px; line-height: 1.6; }
            .button { display: inline-block; background-color: #FF6347; color: #ffffff !important; padding: 15px 30px; font-size: 16px; font-weight: bold; text-decoration: none; border-radius: 5px; }
            .footer { margin-top: 30px; font-size: 12px; color: #777777; }
            .link { word-break: break-all; color: #007bff; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="content">
              <img src="https://alerta-vital-ejvs.vercel.app/AlertaVital.png" alt="Logo de AlertaVital" class="logo">
              <h1>¡Un último paso para activar tu cuenta!</h1>
              <p>Hola, ${user.nombre_completo},</p>
              <p>Gracias por registrarte en AlertaVital. Para completar la configuración y asegurar tu cuenta, por favor, haz clic en el botón de abajo.</p>
              <p>
                <a href="${verificationUrl}" class="button">Verificar mi Correo</a>
              </p>
              <p>Este enlace de verificación es válido por 1 hora.</p>
              <div class="footer">
                <p>Si el botón no funciona, copia y pega el siguiente enlace en tu navegador:</p>
                <p><a href="${verificationUrl}" class="link">${verificationUrl}</a></p>
                <p style="margin-top: 20px;">Si no creaste esta cuenta, puedes ignorar este correo de forma segura.</p>
              </div>
            </div>
          </div>
        </body>
        </html>
      `,
    });

    res.status(201).json({ message: 'Registro exitoso. Por favor, revisa tu correo para verificar tu cuenta.' });

  } catch (e) {
    console.error('[REGISTER_ERROR]', e);
    res.status(500).json({ error: 'Ocurrió un error en el servidor al registrar el usuario.' });
  }
}

export async function verifyEmail(req, res) {
    try {
        const { token } = req.body;
        if (!token) return res.status(400).json({ error: 'Token no proporcionado.' });

        const payload = jwt.verify(token, config.jwtSecret);
        
        if (payload.type !== 'EMAIL_VERIFICATION') {
            return res.status(400).json({ error: 'Token inválido.' });
        }

        await setCorreoVerificado(payload.userId);

        res.json({ message: 'Correo verificado exitosamente. Ya puedes iniciar sesión.' });

    } catch (e) {
        console.error('[VERIFY_EMAIL_ERROR]', e);
        res.status(400).json({ error: 'El enlace de verificación es inválido o ha expirado.' });
    }
}

export async function login(req, res) {
  try {
    const { correo, contrasena } = req.body || {};
    if (!correo || !contrasena) return res.status(400).json({ error: 'Correo y contraseña requeridos.' });
    
    const user = await findUserByEmail(correo);
    if (!user) return res.status(401).json({ error: 'Credenciales inválidas.' });

    if (!user.correo_verificado_en) {
      return res.status(403).json({ error: 'Tu cuenta no ha sido verificada. Por favor, revisa tu correo electrónico.' });
    }

    const passwordIsValid = await verifyPassword(user.contrasena_hash, contrasena);
    if (!passwordIsValid) return res.status(401).json({ error: 'Credenciales inválidas.' });

    await setLastLogin(user.id);
    const token = issueToken(user);
    res.json({ token });
  } catch (e) {
    console.error('[LOGIN_ERROR]', e);
    res.status(500).json({ error: 'Error en el servidor durante el login.' });
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

// Solicitar Reseteo de Contraseña
export async function requestPasswordReset(req, res) {
  try {
    const { correo } = req.body;
    if (!correo) return res.status(400).json({ error: 'Se requiere un correo electrónico.' });

    const user = await findUserByEmail(correo);
    
    // Por seguridad, siempre devolvemos un mensaje de éxito, incluso si el correo no existe.
    // Esto evita que alguien pueda adivinar qué correos están registrados.
    if (user) {
      const resetToken = jwt.sign(
        { userId: user.id, type: 'PASSWORD_RESET' },
        config.jwtSecret,
        { expiresIn: '15m' } // El enlace es válido por 15 minutos
      );

      // La URL debe apuntar a tu nueva página estática de reseteo.
      const resetUrl = `${config.cambiodUrl}?token=${resetToken}`;

      await resend.emails.send({
        from: 'AlertaVital <noreply@alertavital.xyz>',
        to: [user.correo],
        subject: 'Restablece tu contraseña de AlertaVital',
        html: `
          <!DOCTYPE html>
          <html lang="es">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              body { margin: 0; padding: 0; background-color: #f2f0f9; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
              .container { max-width: 600px; margin: 40px auto; background-color: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.05); border-top: 5px solid #6A5ACD; }
              .content { padding: 40px; text-align: center; color: #333333; }
              .logo { max-width: 130px; margin: 0 auto 30px auto; }
              h1 { font-size: 24px; margin-bottom: 15px; }
              p { margin-bottom: 25px; font-size: 16px; line-height: 1.6; }
              .button { display: inline-block; background-color: #FF6347; color: #ffffff !important; padding: 15px 30px; font-size: 16px; font-weight: bold; text-decoration: none; border-radius: 5px; }
              .footer { margin-top: 30px; font-size: 12px; color: #777777; }
              .link { word-break: break-all; color: #007bff; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="content">
                <img src="https://alerta-vital-ejvs.vercel.app/AlertaVital.png" alt="Logo de AlertaVital" class="logo">
                <h1>¿Olvidaste tu contraseña?</h1>
                <p>Recibimos una solicitud para restablecer la contraseña de tu cuenta. Haz clic en el botón de abajo para crear una nueva.</p>
                <p>
                  <a href="${resetUrl}" class="button">Restablecer Contraseña</a>
                </p>
                <p>Este enlace es válido por 15 minutos.</p>
                <div class="footer">
                  <p>Si el botón no funciona, copia y pega el siguiente enlace en tu navegador:</p>
                  <p><a href="${resetUrl}" class="link">${resetUrl}</a></p>
                  <p style="margin-top: 20px;">Si no solicitaste este cambio, puedes ignorar este correo de forma segura.</p>
                </div>
              </div>
            </div>
          </body>
          </html>
        `,
      });
    }

    res.json({ message: 'Si tu correo está registrado, recibirás un enlace para restablecer tu contraseña.' });

  } catch (e) {
    console.error('[REQUEST_RESET_ERROR]', e);
    res.status(500).json({ error: 'Ocurrió un error en el servidor.' });
  }
}

// Confirmar Reseteo de Contraseña
export async function resetPassword(req, res) {
    try {
        const { token, newPassword } = req.body;

        if (!token || !newPassword) return res.status(400).json({ error: 'Token y nueva contraseña son requeridos.' });
        if (newPassword.length < 6) return res.status(400).json({ error: 'La contraseña debe tener al menos 6 caracteres.' });

        const payload = jwt.verify(token, config.jwtSecret);
        
        if (payload.type !== 'PASSWORD_RESET') {
            return res.status(400).json({ error: 'Token inválido para esta acción.' });
        }

        // Llama al servicio para hashear y guardar la nueva contraseña
        await updatePassword(payload.userId, newPassword);

        res.json({ message: 'Contraseña actualizada exitosamente. Ya puedes iniciar sesión con tu nueva contraseña.' });

    } catch (e) {
        console.error('[RESET_PASSWORD_ERROR]', e);
        res.status(400).json({ error: 'El enlace para restablecer la contraseña es inválido o ha expirado.' });
    }
}