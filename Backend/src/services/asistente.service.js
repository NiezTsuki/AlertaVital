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
    
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" }); 
    
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 1024, 
      },
    });

    const contentParts = [{ text: textoUsuario }];
    const result = await chat.sendMessage(contentParts); 
    const response = result.response;
    
    // --- CORRECCIÓN CLAVE ---
    // Se obtiene el texto llamando a la función text()
    const textoRespuesta = response.text();
    
    if (!response || !textoRespuesta) {
        console.error("[GEMINI_ERROR] Respuesta nula o vacía de la IA.");
        throw new Error("La IA no pudo generar una respuesta.");
    }
    
    // Se devuelve el string con la respuesta correcta
    return textoRespuesta; 

  } catch (error) {
    console.error("💥 [GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error(`Error de IA. Mensaje: ${error.message || error}`);
  }
}