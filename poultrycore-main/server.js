const { parse } = require('url')
const path = require('path')
const next = require('next')

// For IISNode, we don't control the server - IIS does
// We just need to prepare Next.js and export a request handler
const dev = process.env.NODE_ENV !== 'production'

// Get the directory where server.js is located
const dir = __dirname

console.log('Initializing Next.js app...')
console.log('Directory:', dir)
console.log('NODE_ENV:', process.env.NODE_ENV)
console.log('Dev mode:', dev)

// Initialize Next.js app
const app = next({ 
  dev, 
  dir: dir,
  conf: {
    distDir: '.next'
  }
})

const handle = app.getRequestHandler()

// Prepare the app synchronously before exporting handler
let appReady = false
let appError = null

// Start preparing immediately
app.prepare()
  .then(() => {
    appReady = true
    console.log('> Next.js app prepared and ready for IISNode')
    console.log('> Build directory:', path.join(dir, '.next'))
  })
  .catch((err) => {
    appError = err
    console.error('> Error preparing Next.js app:', err)
    console.error('> Error stack:', err.stack)
    // Don't exit - let IISNode handle it
  })

// Export the request handler for IISNode
// IISNode will call this function for each request
module.exports = async function(req, res) {
  // If there was an error during preparation, return error
  if (appError) {
    console.error('App preparation failed, returning error')
    if (!res.headersSent) {
      res.statusCode = 500
      res.setHeader('Content-Type', 'text/html')
      res.end(`
        <html>
          <body>
            <h1>Application Error</h1>
            <p>Failed to initialize Next.js application.</p>
            <pre>${appError.message}</pre>
            <p>Check server logs for details.</p>
          </body>
        </html>
      `)
    }
    return
  }
  
  // Wait for app to be ready if it's not yet
  if (!appReady) {
    try {
      await app.prepare()
      appReady = true
      console.log('> App prepared on first request')
    } catch (err) {
      console.error('> Error preparing app on first request:', err)
      if (!res.headersSent) {
        res.statusCode = 500
        res.setHeader('Content-Type', 'text/html')
        res.end(`
          <html>
            <body>
              <h1>Application Initialization Error</h1>
              <p>Failed to prepare Next.js application.</p>
              <pre>${err.message}</pre>
              <p>Check that .next folder exists and is complete.</p>
            </body>
          </html>
        `)
      }
      return
    }
  }
  
  try {
    const parsedUrl = parse(req.url, true)
    await handle(req, res, parsedUrl)
  } catch (err) {
    console.error('Error occurred handling', req.url, err)
    console.error('Error stack:', err.stack)
    if (!res.headersSent) {
      res.statusCode = 500
      res.setHeader('Content-Type', 'text/html')
      res.end(`
        <html>
          <body>
            <h1>Request Handling Error</h1>
            <p>An error occurred while processing your request.</p>
            <pre>${err.message}</pre>
          </body>
        </html>
      `)
    }
  }
}

