export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { 
        status: 405,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
       });
    }

    try {
      const data = await request.json();
      const { formType, ...fields } = data;

      // Subject nach Formular
      let subject = "Neue Nachricht von Allegra-Formular";
      if (formType === "Anmeldung als Teilnehmer*in") subject = "Neue Anmeldung";
      if (formType === "Angebot registrieren") subject = "Neue Gruppen-Registrierung";

      // Body
      let body = `Formular: ${formType}\n\n`;
      for (const [key, value] of Object.entries(fields)) {
        body += `${key}: ${value}\n`;
      }

      // Resend API call
      const resp = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${env.RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: env.FROM_EMAIL,
          to: [env.TO_EMAIL],
          reply_to: fields.email || env.TO_EMAIL,
          subject: subject,
          text: body,
        }),
      });

      const text = await resp.text();
      return new Response(
        `Resend response: ${resp.status} - ${text}`,
        { status: resp.ok ? 200 : 500,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
          },
        }
      );

    } catch (err) {
      return new Response("Bad Request: " + err.message, { 
        status: 400,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }
  },
};
