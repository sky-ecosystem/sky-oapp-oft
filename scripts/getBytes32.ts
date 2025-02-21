import bs58 from 'bs58'

// Function to convert base58 string to bytes32
function base58ToBytes32(base58String: string): string {
  // Decode base58 string to Uint8Array
  const decoded = bs58.decode(base58String)
  
  // Ensure the decoded bytes are exactly 32 bytes
  if (decoded.length > 32) {
    throw new Error('Input base58 string decodes to more than 32 bytes')
  }
  
  // Create a new Uint8Array of 32 bytes filled with zeros
  const paddedArray = new Uint8Array(32)
  
  // Copy the decoded bytes to the end of the padded array
  paddedArray.set(decoded, 32 - decoded.length)
  
  // Convert to hex string with '0x' prefix
  const bytes32 = '0x' + Buffer.from(paddedArray).toString('hex')
  
  return bytes32
}

// Example usage
const base58String = '3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a'
try {
  const bytes32 = base58ToBytes32(base58String)
  console.log('Input (base58):', base58String)
  console.log('Output (bytes32):', bytes32)
} catch (error: any) {
  console.error('Error:', error.message)
}
