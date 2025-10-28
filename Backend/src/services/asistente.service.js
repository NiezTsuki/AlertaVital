import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

// Inicialización de genAI con la variable de entorno.
// Esta es la forma segura y optimizada para entornos serverless.
const genAI = new GoogleGenerativeAI(config.geminiApiKey); 

export async function conversarConGemini(textoUsuario, historial) {
  try {
    // Verificar que la clave se haya cargado correctamente
    if (!config.geminiApiKey) {
      console.error("[GEMINI_ERROR] Clave de API no cargada en config/env.js");
      throw new Error("Clave API de Gemini no configurada.");
    }
    
    // 1. Uso normal con el modelo gemini-2.5-flash
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" }); 
    
    // 2. Chat setup
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 200, 
      },
    });

    // 3. Envío del mensaje como array de partes (solución a request is not iterable)
    const contentParts = [{ text: textoUsuario }];
    const result = await chat.sendMessage(contentParts); 
    const response = result.response;
    
    // 4. Verificación de respuesta
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta nula/vacía.");
        throw new Error("La IA no pudo generar una respuesta.");
    }

    return response.text; 

  } catch (error) {
    console.error("💥 [GEMINI_ERROR] Fallo al procesar la IA:", error);
    // Lanzamos un error legible que Express maneja con el código 500
    throw new Error(`Error de IA. Mensaje: ${error.message || error}`);
  }
}
