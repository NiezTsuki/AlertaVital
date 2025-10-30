import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

// Inicialización de genAI con la variable de entorno.
const genAI = new GoogleGenerativeAI(config.geminiApiKey); 

export async function conversarConGemini(textoUsuario, historial) {
  try {
    if (!config.geminiApiKey) {
      console.error("[GEMINI_ERROR] Clave de API no cargada en config/env.js");
      throw new Error("Clave API de Gemini no configurada.");
    }
    
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" }); 
    
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        // CORRECCIÓN CONFIRMADA: Límite aumentado a 1024
        maxOutputTokens: 1024, 
      },
    });

    const contentParts = [{ text: textoUsuario }];
    const result = await chat.sendMessage(contentParts); 
    const response = result.response;
    
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta nula/vacía.");
        throw new Error("La IA no pudo generar una respuesta.");
    }
    
    // **MEJORA CLAVE:** Se devuelve el texto, Express lo serializará y lo escapará.
    return response.text; 

  } catch (error) {
    console.error("💥 [GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error(`Error de IA. Mensaje: ${error.message || error}`);
  }
}