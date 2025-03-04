import {
    Commitment,
    Connection,
    GetAccountInfoConfig,
    PublicKey,
    TransactionInstruction,
} from '@solana/web3.js'

import { EndpointProgram, EventPDADeriver, SimpleMessageLibProgram, UlnProgram } from '@layerzerolabs/lz-solana-sdk-v2'

import * as accounts from './generated/oft/accounts'
import * as instructions from './generated/oft/instructions'
import * as types from './generated/oft/types'
import { OFTPDADeriver } from './oft-pda-deriver'

export { accounts, instructions, types }

export class OFTProgram {
    oftDeriver: OFTPDADeriver

    constructor(
        public readonly program: PublicKey
    ) {
        this.oftDeriver = new OFTPDADeriver(program)
    }

    oftStorePDA(): PublicKey {
        return this.oftDeriver.oft()
    }

    async executeTwoLegSend(connection: Connection, payer: PublicKey, params: types.ExecuteTwoLegSendParams): Promise<TransactionInstruction> {
        const oftStore = this.oftStorePDA()
        console.log('oftStore', oftStore.toBase58())
        
        const ix = instructions.createExecuteTwoLegSendInstruction(
            {
                signer: payer,
                peer: new PublicKey('EZ4hoYu18tVZBYjw7rdVGahHbyuwakukw2zHNvvMHyjR'),
                oftStore: new PublicKey('HUPW9dJZxxSafEVovebGxgbac3JamjMHXiThBxY5u43M'),
                tokenSource: new PublicKey('CLJeKEMzNWB3TZqN99j4NjgvzNME38o46iSJPWZHsa7e'),
                tokenEscrow: new PublicKey('HwpzV5qt9QzYRuWkHqTRuhbqtaMhapSNuriS5oMynkny'),
                tokenMint: new PublicKey('AtGakZsHVY1BkinHEFMEJxZYhwA9KnuLD8QRmGjSAZEC'),
                twoLegSendPendingMessageStore: new PublicKey('6wvGC9hxTkaFRdaDrXTQVfcRMBkwezBYHduuoYeSDNKm'),
                eventAuthority: new PublicKey('CHdj1mbPqeoR9mB9exJLarToNrpMEjAnaGjrgkYhTpPZ'),
                program: this.program,
            } satisfies instructions.ExecuteTwoLegSendInstructionAccounts,
            {
                params,
            },
            this.program
        )

        return ix;
    }
    
}