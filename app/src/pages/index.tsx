
import { useState, useEffect } from 'react';
import QRCode from 'react-qr-code';
import { ReclaimProofRequest, transformForOnchain } from '@reclaimprotocol/js-sdk';
import { privateKeyToAccount } from 'viem/accounts'
import { baseSepolia } from 'viem/chains';
import { createPublicClient, createWalletClient } from 'viem';
import { http } from 'viem';
import { getContract } from 'viem'
import abi from "/Users/tanbajintaro/Development/FCPM/fcpm/out/zkTLSOracle.sol/Oracle.json"
function ReclaimDemo() {

  // State to store the verification request URL
  const [requestUrl, setRequestUrl] = useState('');
  const [proofs, setProofs] = useState([]);
  const [client, setClient] = useState<any>(null);

  useEffect(() => {
    console.log(abi.abi);
  }, []);

  
  async function executeFn(proof: any) {
    const privateKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const oracleAddress = "0xD0590A4A79927cca51bC44f3803194aA8DA64727";

    const account = privateKeyToAccount(privateKey);
    const publicClient = createPublicClient({
      chain: baseSepolia,
      transport: http("http://localhost:8545")
    })
    const blockNumber = await publicClient.getBlockNumber();
    console.log("blockNumber ----",blockNumber);
    const walletClient = createWalletClient({
      account,
      chain: baseSepolia,
      transport: http("http://localhost:8545")
    })
    const onchainProof = transformForOnchain(proof);
    // const [account] = await walletClient.getAddresses()
    console.log("onchainProof", onchainProof);
    const { request } = await publicClient.simulateContract({
      account: account.address,
      address: oracleAddress,
      abi: abi.abi,
      functionName: 'resolveMarket',
      args: [
        1,
        onchainProof
      ],
    })
    // const { request } = await publicClient.simulateContract({
    //   account: account.address,
    //   address: oracleAddress,
    //   abi: abi.abi,
    //   functionName: 'createMarketWithZKP',
    //   args: [
    //     0,100,10,120,
    //     onchainProof,         // proof（JSON.stringifyせずに直接渡す）
    //   ],
    // })
    console.log("request",request);
    walletClient.writeContract(request)

  }
 
  const getVerificationReq = async () => {

    // Your credentials from the Reclaim Developer Portal
    // Replace these with your actual credentials

    const APP_ID = '0x6574224D597C240fec40E5197e12F1F7dbbD711b';
    const APP_SECRET = '0xd9f36c450658e6a9fdef357a5612fc9a01aae38701e210c8c3b2598e0639eded';
    const PROVIDER_ID = '30c5c663-6cdf-4f53-a225-a8e390db66d5';
 
    // Initialize the Reclaim SDK with your credentials
    const reclaimProofRequest = await ReclaimProofRequest.init(APP_ID, APP_SECRET, PROVIDER_ID);
 
    // Generate the verification request URL
    const requestUrl = await reclaimProofRequest.getRequestUrl();

    console.log('Request URL:', requestUrl);

    setRequestUrl(requestUrl);
 
    // Start listening for proof submissions
    await reclaimProofRequest.startSession({

      // Called when the user successfully completes the verification
      onSuccess: (proofs) => {

        console.log('Verification success', proofs);
        setProofs(proofs as any);
        executeFn(proofs as any);
      },
      // Called if there's an error during verification
      onError: (error) => {

        console.error('Verification failed', error);
 
        // Add your error handling logic here, such as:
        // - Showing error message to user
        // - Resetting verification state
        // - Offering retry options
      },
    });
  };
 
  return (
    <>
      <button onClick={getVerificationReq}>Get Verification Request</button>

      {/* Display QR code when URL is available */}

      {requestUrl && (
        <div style={{ margin: '20px 0' }}>
          <QRCode value={requestUrl} />
        </div>
      )}

      {proofs && (
        <div>
          <h2>Verification Successful!</h2>
          <pre>{JSON.stringify(proofs, null, 2)}</pre>
        </div>
      )}
    </>
  );
}
 
export default ReclaimDemo;
