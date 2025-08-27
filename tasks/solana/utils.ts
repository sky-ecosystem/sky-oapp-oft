import { ErrorWithLogs, ProgramError, Transaction, Umi } from '@metaplex-foundation/umi'
import { toWeb3JsTransaction } from '@metaplex-foundation/umi-web3js-adapters'
import { Connection, PublicKey } from '@solana/web3.js'
import { backOff } from 'exponential-backoff'

/**
 * Assert that the account is initialized on the Solana blockchain.  Due to eventual consistency, there is a race
 * between account creation and initialization.  This function will retry 10 times with backoff to ensure the account is
 * initialized.
 * @param connection {Connection}
 * @param publicKey {PublicKey}
 */
export const assertAccountInitialized = async (connection: Connection, publicKey: PublicKey) => {
    return backOff(
        async () => {
            const accountInfo = await connection.getAccountInfo(publicKey)
            if (!accountInfo) {
                throw new Error('Multisig account not found')
            }
            return accountInfo
        },
        {
            maxDelay: 30000,
            numOfAttempts: 10,
            startingDelay: 5000,
        }
    )
}

export const simulateTransaction = async (
    context: Umi,
    transaction: Transaction,
    connection: Connection,
    options: { verifySignatures?: boolean; } = {}
  ) => {
    try {
      const tx = toWeb3JsTransaction(transaction);
      const result = await connection.simulateTransaction(tx, {
        sigVerify: options.verifySignatures,
      });
      return result.value;
    } catch (error: any) {
      let resolvedError: ProgramError | null = null;
      if (error instanceof Error && 'logs' in error) {
        resolvedError = context.programs.resolveError(
          error as ErrorWithLogs,
          transaction
        );
      }
      throw resolvedError || error;
    }
  };