import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

const genAI = new GoogleGenerativeAI(config.geminiApiKey);

export async function conversarConGemini(textoUsuario, historial) {
  try {
    // Usamos el modelo correcto que ya resolviste
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" }); 
    
    // Inicia una conversación con historial
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 200, 
      },
    });
    
    // ********** CORRECCIÓN CRÍTICA **********
    // Enviamos el texto envuelto en un objeto { text: '...' } 
    // para cumplir con el formato esperado por el SDK y resolver el TypeError.
    const result = await chat.sendMessage({ text: textoUsuario });
    // ****************************************
    
    const response = result.response;
    
    // Verificación final para asegurar que la respuesta no esté vacía
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta vacía o nula del modelo.");
        // Devolvemos un error para que el frontend lo maneje.
        throw new Error("El modelo no pudo generar una respuesta. (Puede ser clave inválida)");
    }
    
    return response.text; 

  } catch (error) {
    console.error("[GEMINI_ERROR] Fallo al procesar la IA:", error);
    // Aseguramos que se lance un Error para que Express devuelva un 500
    throw new Error(`Problema al conectar con la IA. Mensaje: ${error.message || error}`);
  }
}
