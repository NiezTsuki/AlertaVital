import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

// *** ¡ADVERTENCIA DE SEGURIDAD! ESTO ES SOLO PARA PRUEBAS! ***
// La clave está fija aquí para descartar el error de inyección de Vercel.
// REEMPLAZA ESTA CADENA CON LA CLAVE COMPLETA QUE USÓ EN CURL:
const CLAVE_DIRECTA = "AIzaSyB-0_8f1_HjdcPh5Ni5uh7rcmmv2MKOhjQ"; // <--- CLAVE HARDCODEADA AQUÍ

// La inicialización usa la clave HARDCODEADA para el test final.
const genAI = new GoogleGenerativeAI(CLAVE_DIRECTA); 
// *************************************************************

export async function conversarConGemini(textoUsuario, historial) {
  try {
    // Si la clave es inválida, este es el punto de falla final.
    if (!CLAVE_DIRECTA || CLAVE_DIRECTA.length < 10) {
      console.error("[GEMINI_ERROR] Clave no definida en el código.");
      throw new Error("Clave API de Gemini no definida.");
    }
    
    // 1. USO NORMAL
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" }); 
    
    // 2. CHAT SETUP
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 200, 
      },
    });

    const contentParts = [{ text: textoUsuario }];
    const result = await chat.sendMessage(contentParts); 
    const response = result.response;
    
    // Verificación de respuesta
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta nula/vacía. Probable fallo de la clave.");
        throw new Error("La IA no pudo generar una respuesta.");
    }

    return response.text; 

  } catch (error) {
    console.error("💥 [GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error(`Problema al conectar con la IA. Mensaje: ${error.message || error}`);
  }
}
