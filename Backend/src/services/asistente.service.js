import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

// ELIMINAR ESTA LÍNEA: const genAI = new GoogleGenerativeAI(config.geminiApiKey); 
// Inicializaremos dentro de la función.

export async function conversarConGemini(textoUsuario, historial) {
  try {
    // 1. INICIALIZACIÓN MOVIMIENTO DENTRO DE LA FUNCIÓN
    const geminiApiKey = config.geminiApiKey;
    if (!geminiApiKey) {
      console.error("[GEMINI_ERROR] Clave no cargada en Vercel.");
      throw new Error("Clave API de Gemini no configurada en Vercel.");
    }
    const genAI = new GoogleGenerativeAI(geminiApiKey);
    
    // 2. USO NORMAL
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" }); 
    
    // ... (resto del código igual)
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 200, 
      },
    });

    const contentParts = [{ text: textoUsuario }];
    const result = await chat.sendMessage(contentParts); 
    const response = result.response;
    
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta nula. Revisar latencia.");
        throw new Error("El modelo no pudo generar una respuesta.");
    }

    return response.text; 

  } catch (error) {
    console.error("💥 [GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error(`Problema al conectar con la IA. Mensaje: ${error.message || error}`);
  }
}
