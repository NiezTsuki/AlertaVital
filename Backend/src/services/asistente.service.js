import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

// ********** CORRECCIÓN: Inicialización global y final **********
// La variable de entorno ya debe estar cargada en este punto.
const genAI = new GoogleGenerativeAI(config.geminiApiKey); 
// *************************************************************

export async function conversarConGemini(textoUsuario, historial) {
  try {
    // ELIMINAR TODA LA LÓGICA DE CARGA DE CLAVE AQUÍ PARA MAXIMIZAR LA VELOCIDAD
    
    // Si la clave no se cargó globalmente, esto fallará, lo cual es correcto.
    if (!config.geminiApiKey) {
      console.error("[GEMINI_ERROR] Clave de API no configurada al inicio del módulo.");
      throw new Error("Clave API de Gemini no configurada en Vercel.");
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
        // Si no responde, la latencia es demasiado alta o el servicio está bloqueado.
        console.error("[GEMINI_ERROR] Respuesta nula/vacía a pesar del 200 OK.");
        throw new Error("La IA no pudo generar una respuesta (Timeout).");
    }

    return response.text; 

  } catch (error) {
    console.error("💥 [GEMINI_ERROR] Fallo al procesar la IA:", error);
    throw new Error(`Problema al conectar con la IA. Mensaje: ${error.message || error}`);
  }
}
