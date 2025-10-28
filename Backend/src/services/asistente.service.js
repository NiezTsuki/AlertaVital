import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

const genAI = new GoogleGenerativeAI(config.geminiApiKey);

export async function conversarConGemini(textoUsuario, historial) {
  try {
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" }); 
    
    // Inicia una conversación con historial
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 200, 
      },
    });

    const result = await chat.sendMessage({ text: textoUsuario }); // Asegúrate que el texto se envía como objeto.
    const response = result.response;
    
    // ********** AÑADIDO PARA DEBUGGING **********
    console.log("[GEMINI_RESPONSE_DEBUG] Full Response:", JSON.stringify(response)); 
    // ********************************************

    // Verifica si la respuesta es válida
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta vacía o nula del modelo.");
        return "El modelo no pudo generar una respuesta.";
    }

    return response.text; // Usar .text sin paréntesis si es una propiedad

  } catch (error) {
    console.error("[GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error("Problema al conectar con la IA. Revisa la clave o el modelo.");
  }
}
