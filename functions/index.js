const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.database();

function generateArticleKey(url) {
  const hash = Math.abs(url.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0)).toString(16);
  return `article_${hash.padStart(8, '0')}`;
}

function extractSourceName(url) {
  try {
    const uri = new URL(url);
    return uri.host;
  } catch (_) {
    return 'yallanews';
  }
}

exports.saveNewsArticle = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const article = req.body;
    if (!article || !article.url || !article.title) {
      res.status(400).json({ error: 'Missing required fields: url, title' });
      return;
    }

    const key = generateArticleKey(article.url);
    const payload = {
      title: article.title,
      summary: article.summary || '',
      content: article.content || '',
      language: article.language || 'ar',
      category: article.category || 'general',
      source: {
        name: extractSourceName(article.url),
        url: article.url,
        score: article.source?.score ?? 0.85,
      },
      sourceUrl: article.url,
      imageUrl: article.imageUrl || '',
      publishedAt: Date.now(),
      status: article.status || 'published',
    };

    const ref = db.ref(`news/${key}`);
    await ref.set(payload);

    res.status(200).json({ key, message: 'Article saved successfully' });
  } catch (error) {
    console.error('Error saving article:', error);
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
});

exports.saveNewsArticles = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const articles = req.body;
    if (!Array.isArray(articles)) {
      res.status(400).json({ error: 'Expected an array of articles' });
      return;
    }

    const results = [];
    for (const article of articles) {
      if (!article || !article.url || !article.title) continue;

      const key = generateArticleKey(article.url);
      const payload = {
        title: article.title,
        summary: article.summary || '',
        content: article.content || '',
        language: article.language || 'ar',
        category: article.category || 'general',
        source: {
          name: extractSourceName(article.url),
          url: article.url,
          score: article.source?.score ?? 0.85,
        },
        sourceUrl: article.url,
        imageUrl: article.imageUrl || '',
        publishedAt: Date.now(),
        status: article.status || 'published',
      };

      await db.ref(`news/${key}`).set(payload);
      results.push({ key, url: article.url });
    }

    res.status(200).json({ saved: results.length, results });
  } catch (error) {
    console.error('Error saving articles:', error);
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
});
