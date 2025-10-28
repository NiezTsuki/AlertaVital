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
    
    // ********** CORRECCIÓN DEFINITIVA: ENVIAR COMO ARREGLO DE PARTES **********
    const contentParts = [{ text: textoUsuario }]; // Creamos un arreglo con el objeto Part
    
    // Usamos el arreglo de partes en sendMessage
    const result = await chat.sendMessage(contentParts); 
    // **************************************************************************
    
    const response = result.response;
    
    // Verificación final para asegurar que la respuesta no esté vacía
    if (!response || !response.text) {
        console.error("[GEMINI_ERROR] Respuesta vacía o nula del modelo.");
        // Devolvemos un error claro.
        throw new Error("El modelo no pudo generar una respuesta. (Puede ser clave inválida o bloqueo de seguridad)");
    }

    return response.text; 

  } catch (error) {
    console.error("[GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error(`Problema al conectar con la IA. Mensaje: ${error.message || error}`);
  }
}