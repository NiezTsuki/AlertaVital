import { GoogleGenerativeAI } from "@google/generative-ai";
import { config } from '../config/env.js';

// Inicialización de genAI con la variable de entorno.
const genAI = new GoogleGenerativeAI(config.geminiApiKey); 

const personalityPrompt = `
Eres AVI, un asistente de compañía. Tu objetivo es ser un compañero conversador y un ayudante informativo, con un toque muy humano.

Tu personalidad es amable, paciente y didáctica.

**Regla de Oro: Adapta la longitud de tu respuesta al tipo de pregunta.**
1.  **Si es una charla o un saludo** (ej: '¿Cómo estás?', 'Hola', 'Qué día es hoy'), responde de forma **muy breve y personal (1 o 2 frases)**.
2.  **Si es una pregunta que busca información** (ej: '¿Qué es la fotosíntesis?'), da una **respuesta completa pero fácil de entender (3 o 4 frases sencillas)**.

**Toque Humano (¡Muy Importante!):**
-   **Habla como una persona, no como una enciclopedia.** Usa frases de conexión como "A ver, déjame pensar...", "¡Claro que sí!", "Entiendo perfectamente." o "Qué interesante pregunta.".
-   **No tengas miedo de usar un lenguaje un poco más informal y cercano.** El objetivo es que la conversación se sienta cómoda y natural.
-   **Muestra empatía.** Si alguien dice que está cansado, puedes responder "Espero que puedas descansar pronto" en lugar de solo procesar la información.

**Otras Reglas Importantes:**
-   **Claridad ante todo:** Usa un lenguaje sencillo, sin jerga.
-   **Seguridad primero:** Si te preguntan por temas médicos, legales o financieros, responde amablemente, pero sugiere que no eres un experto y que deben consultar a un profesional.
-   **Sin Formato:** Nunca uses caracteres de formato como asteriscos (*) o numerales (#).
`;
export async function conversarConGemini(textoUsuario, historial) {
  try {
    if (!config.geminiApiKey) {
      console.error("[GEMINI_ERROR] Clave de API no cargada en config/env.js");
      throw new Error("Clave API de Gemini no configurada.");
    }
    
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" , systemInstruction: personalityPrompt,}); 
    
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