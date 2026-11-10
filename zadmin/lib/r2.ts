import 'server-only'

import { createHash, createHmac } from 'node:crypto'

export type R2Config = { accountId: string; accessKeyId: string; secretAccessKey: string; bucket: string }

export function getR2Config(): R2Config | null {
  const accountId = process.env.R2_ACCOUNT_ID
  const accessKeyId = process.env.R2_ACCESS_KEY_ID
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY
  if (!accountId || !accessKeyId || !secretAccessKey) return null
  return {
    accountId, accessKeyId, secretAccessKey,
    bucket: process.env.R2_BUCKET_NAME || 'ccb-media',
  }
}

function hmac(key: Buffer | string, value: string) {
  return createHmac('sha256', key).update(value).digest()
}

function awsEncode(value: string) {
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`)
}

export function presignR2Request(config: R2Config, method: 'GET' | 'PUT' | 'HEAD', objectKey: string, mimeType?: string, expiresSeconds = 600) {
  const host = `${config.accountId}.r2.cloudflarestorage.com`
  const now = new Date()
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '')
  const dateStamp = amzDate.slice(0, 8)
  const scope = `${dateStamp}/auto/s3/aws4_request`
  const credential = `${config.accessKeyId}/${scope}`
  const canonicalUri = `/${awsEncode(config.bucket)}/${objectKey.split('/').map(awsEncode).join('/')}`
  const signedHeaders = mimeType ? 'content-type;host' : 'host'
  const params: Record<string, string> = {
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Credential': credential,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(expiresSeconds),
    'X-Amz-SignedHeaders': signedHeaders,
  }
  const canonicalQuery = Object.entries(params)
    .map(([key, value]) => [awsEncode(key), awsEncode(value)] as const)
    .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
    .map(([key, value]) => `${key}=${value}`).join('&')
  const canonicalHeaders = mimeType ? `content-type:${mimeType}\nhost:${host}\n` : `host:${host}\n`
  const canonicalRequest = [method, canonicalUri, canonicalQuery, canonicalHeaders, signedHeaders, 'UNSIGNED-PAYLOAD'].join('\n')
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope, createHash('sha256').update(canonicalRequest).digest('hex')].join('\n')
  const dateKey = hmac(`AWS4${config.secretAccessKey}`, dateStamp)
  const regionKey = hmac(dateKey, 'auto')
  const serviceKey = hmac(regionKey, 's3')
  const signingKey = hmac(serviceKey, 'aws4_request')
  const signature = createHmac('sha256', signingKey).update(stringToSign).digest('hex')
  return `https://${host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`
}
