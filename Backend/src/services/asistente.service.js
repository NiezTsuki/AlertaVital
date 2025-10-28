import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

const genAI = new GoogleGenerativeAI(config.geminiApiKey);

export async function conversarConGemini(textoUsuario, historial) {
  try {
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
    
    // Inicia una conversación con historial para que recuerde cosas
    const chat = model.startChat({
      history: historial,
      generationConfig: {
        maxOutputTokens: 200, // Limita la longitud de la respuesta
      },
    });

    const result = await chat.sendMessage(textoUsuario);
    const response = await result.response;
    return response.text();

  } catch (error) {
    console.error("[GEMINI_ERROR]", error);
    return "Lo siento, estoy teniendo problemas para conectarme en este momento.";
  }
}