import { NextRequest, NextResponse } from 'next/server'

// Never cache — each request must hit the live backend
export const dynamic = 'force-dynamic'

// Proxy API route: browser calls same-origin /api/proxy/...; this handler forwards server-side (no browser CORS).

function normalizeBaseUrl(apiBase: string): string {
  const trimmed = apiBase.trim().replace(/\/+$/, '')
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed
  }
  if (trimmed.includes('localhost')) {
    return `http://${trimmed}`
  }
  return `https://${trimmed}`
}

function getApiBaseUrl(pathSegments: string[]): string {
  const isAdminApi =
    pathSegments[0] === 'Admin' ||
    pathSegments[0] === 'Authentication' ||
    pathSegments[0] === 'Payments' ||
    pathSegments[0] === 'UserProfile'

  // ADMIN_API_URL = server-only override (Render secrets). Else NEXT_PUBLIC_* from build/runtime.
  const apiBase = isAdminApi
    ? process.env.LOGIN_API_URL ||
      process.env.NEXT_PUBLIC_LOGIN_API_URL ||
      process.env.ADMIN_API_URL ||
      process.env.NEXT_PUBLIC_ADMIN_API_URL ||
      'usermanagementapi.techretainer.com'
    : process.env.FARM_API_URL ||
      process.env.NEXT_PUBLIC_API_BASE_URL ||
      'farmapi.techretainer.com'

  return normalizeBaseUrl(apiBase)
}

/** Shown when the proxy gives up waiting on Login/Admin Cloud Run (cold start, DB hang). */
function loginAdminTimeoutHelp(apiBaseUrl: string): string {
  return (
    `Login flow: browser → this site’s /api/proxy/Authentication/* → forwards to:\n${apiBaseUrl}\n\n` +
    `Checks:\n` +
    `• Redeploy the frontend after code/env changes (Next must serve /api/proxy).\n` +
    `• On Render/hosting: set NEXT_PUBLIC_ADMIN_API_URL and ADMIN_API_URL to your Login Cloud Run URL (full https://….run.app).\n` +
    `• GCP → Cloud Run → Login service → Logs: fix startup if the container crashes (DB connection string, JWT, etc.).\n` +
    `• From your PC: curl -sI "${apiBaseUrl}/" — expect HTTP 200 or 404 from the app, not timeout.`
  )
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params
  return handleRequest(request, path, 'GET')
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params
  return handleRequest(request, path, 'POST')
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params
  return handleRequest(request, path, 'PUT')
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params
  return handleRequest(request, path, 'DELETE')
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params
  return handleRequest(request, path, 'PATCH')
}

async function handleRequest(
  request: NextRequest,
  pathSegments: string[],
  method: string
) {
  try {
    const apiBaseUrl = getApiBaseUrl(pathSegments)
    const path = pathSegments.join('/')
    
    // Get the full URL with query parameters
    const searchParams = request.nextUrl.searchParams.toString()
    const queryString = searchParams ? `?${searchParams}` : ''
    const targetUrl = `${apiBaseUrl}/api/${path}${queryString}`

    // Get headers from the incoming request (except problematic ones)
    const headers = new Headers()
    // Headers that should NOT be forwarded to backend
    const skipHeaders = [
      'host', 
      'content-length', 
      'expect',              // Node.js fetch doesn't support Expect header
      'connection',          // Don't forward connection-specific headers
      'transfer-encoding',   // Let fetch handle transfer encoding
      'upgrade',             // Don't forward upgrade headers
      'keep-alive',          // Don't forward keep-alive headers
    ]
    
    request.headers.forEach((value, key) => {
      // Skip headers that shouldn't be forwarded
      if (!skipHeaders.includes(key.toLowerCase())) {
        headers.set(key, value)
      }
    })

    // Prepare fetch options
    const fetchOptions: RequestInit = {
      method,
      headers,
    }

    // Add body for methods that support it
    if (['POST', 'PUT', 'PATCH'].includes(method)) {
      const body = await request.text()
      if (body) {
        fetchOptions.body = body
        // Log request body for debugging (limit to first 2000 chars to avoid huge logs)
        try {
          const bodyPreview = body.length > 2000 ? body.substring(0, 2000) + '...' : body
          console.log('[Proxy API] Request body:', bodyPreview)
          // Try to parse and log as JSON for better readability
          try {
            const bodyJson = JSON.parse(body)
            console.log('[Proxy API] Request body (parsed):', JSON.stringify(bodyJson, null, 2))
          } catch {
            // Not JSON, log as-is
          }
        } catch (e) {
          console.log('[Proxy API] Could not log request body:', e)
        }
      } else {
        console.log('[Proxy API] No request body found')
      }
    }

    // Forward the request to the backend API
    const isAdminPath =
      pathSegments[0] === 'Admin' ||
      pathSegments[0] === 'Authentication' ||
      pathSegments[0] === 'Payments' ||
      pathSegments[0] === 'UserProfile'
    console.log(
      `[Proxy API] ${isAdminPath ? 'Login/Admin' : 'Farm'} API → ${method} ${targetUrl}`
    )
    console.log('[Proxy API] Request headers:', Object.fromEntries(headers.entries()))

    // Login/Admin: allow longer (Cloud Run cold start + SQL). Farm: keep shorter.
    const upstreamTimeoutMs = isAdminPath ? 75_000 : 30_000
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), upstreamTimeoutMs)

    let response: Response
    try {
      response = await fetch(targetUrl, {
        ...fetchOptions,
        signal: controller.signal,
      })
    } catch (fetchErr: any) {
      if (fetchErr?.name === 'AbortError') {
        console.error('[Proxy API] Upstream fetch aborted (timeout)', {
          targetUrl,
          upstreamTimeoutMs,
        })
        const msg = isAdminPath
          ? `Login API did not respond in time (${upstreamTimeoutMs / 1000}s).\n\n${loginAdminTimeoutHelp(apiBaseUrl)}`
          : `Farm API did not respond in time (${upstreamTimeoutMs / 1000}s). Check Cloud Run Farm logs and ConnectionStrings__PoultryConn.`
        return NextResponse.json(
          {
            success: false,
            message: msg,
            errorType: 'AbortError',
            errorCode: 'PROXY_UPSTREAM_TIMEOUT',
          },
          { status: 504 }
        )
      }
      throw fetchErr
    } finally {
      clearTimeout(timeoutId)
    }
    
    console.log('[Proxy API] Response status:', response.status, response.statusText)
    console.log('[Proxy API] Response headers:', Object.fromEntries(response.headers.entries()))

    // Handle 204 No Content - no body to read
    if (response.status === 204) {
      return new NextResponse(null, {
        status: 204,
        statusText: response.statusText,
      })
    }

    // Get response body for other status codes
    const contentType = response.headers.get('content-type') || ''
    let body: any
    
    try {
      // Try to read response as text first (safer than assuming JSON)
      const textBody = await response.text()
      
      if (textBody && textBody.trim()) {
        // We have a body, parse it appropriately
        if (contentType.includes('application/json') || contentType.includes('text/json')) {
          try {
            body = JSON.parse(textBody)
          } catch (e) {
            // If JSON parsing fails, use the text
            console.warn('[Proxy API] Failed to parse JSON, using text:', e)
            body = { message: textBody, raw: textBody }
          }
        } else {
          // Try to parse as JSON if it looks like JSON
          if (textBody.trim().startsWith('{') || textBody.trim().startsWith('[')) {
            try {
              body = JSON.parse(textBody)
            } catch {
              body = { message: textBody, raw: textBody }
            }
          } else {
            body = { message: textBody, raw: textBody }
          }
        }
      } else {
        // Empty body - return empty object
        body = {}
      }
      
      // Log error responses for debugging
      if (response.status >= 400) {
        console.error('[Proxy API] Error response body:', JSON.stringify(body, null, 2))
        console.error('[Proxy API] Error response status:', response.status, response.statusText)
        console.error('[Proxy API] Target URL that failed:', targetUrl)
        console.error('[Proxy API] Upstream Content-Type was:', contentType || '(none)')
      }
    } catch (error) {
      console.error('[Proxy API] Error reading response body:', error)
      body = { error: 'Failed to read response body', details: error instanceof Error ? error.message : String(error) }
    }

    // NextResponse.json sets application/json; never forward upstream Content-Type (ASP.NET 500 HTML would break the client)
    const nextResponse = NextResponse.json(body, {
      status: response.status,
      statusText: response.statusText,
    })

    const skipResponseHeaders = [
      'content-encoding',
      'content-length',
      'transfer-encoding',
      'content-type', // critical: upstream text/html was overwriting application/json
    ]

    response.headers.forEach((value, key) => {
      if (!skipResponseHeaders.includes(key.toLowerCase())) {
        nextResponse.headers.set(key, value)
      }
    })

    nextResponse.headers.set('Content-Type', 'application/json; charset=utf-8')

    return nextResponse
  } catch (error: any) {
    console.error('[Proxy API] Error forwarding request:', error)
    console.error('[Proxy API] Error name:', error?.name)
    console.error('[Proxy API] Error cause:', error?.cause)
    console.error('[Proxy API] Full error:', JSON.stringify(error, Object.getOwnPropertyNames(error), 2))
    
    // Provide more detailed error information
    const errorMessage = error?.cause?.message || error?.message || 'Failed to forward request to backend API'
    const errorDetails = {
      success: false,
      message: errorMessage,
      errorType: error?.name || 'Unknown',
      errorCode: error?.cause?.code || error?.code || null,
    }
    
    return NextResponse.json(errorDetails, { status: 500 })
  }
}

