import { Coders } from "@phala/ethers";
import "@phala/pink-env";

type HexString = `0x${string}`;

// eth abi coder
const uintCoder = new Coders.NumberCoder(32, false, "uint256");
const bytesCoder = new Coders.BytesCoder("bytes");

function encodeReply(reply: [number, number, number]): HexString {
	return Coders.encode([uintCoder, uintCoder, uintCoder], reply) as HexString;
}

// Defined in TestLensOracle.sol
const TYPE_RESPONSE = 0;
const TYPE_ERROR = 2;

enum Error {
	BadFactorSid = "BadFactorSid",
	FailedToFetchData = "FailedToFetchData",
	FailedToDecode = "FailedToDecode",
	MalformedRequest = "MalformedRequest",
	ErrorWhileParse = "ErrorWhileParse",
}

function errorToCode(error: Error): number {
	switch (error) {
		case Error.BadFactorSid:
			return 1;
		case Error.FailedToFetchData:
			return 2;
		case Error.FailedToDecode:
			return 3;
		case Error.MalformedRequest:
			return 4;
		case Error.ErrorWhileParse:
			return 5;
		default:
			return 0;
	}
}

function stringToHex(str: string): string {
	var hex = "";
	for (var i = 0; i < str.length; i++) {
		hex += str.charCodeAt(i).toString(16);
	}
	return "0x" + hex;
}

function getFactor(factorHash: string) {
	let headers = {
		Authorization: "miral",
	};

	let response = pink.batchHttpRequest(
		[
			{
				url: `https://phala-flex.vercel.app/api/factor?factorHash=${factorHash}`,
				method: "GET",
				headers,
				returnTextBody: true,
			},
		],
		10000
	)[0];

	console.log(JSON.parse(response.body as string));

	const parsedBody = JSON.parse(response.body as string);
	console.log(parsedBody);

	return parsedBody.factor;
}

function checkAuthyOTP(
	otp: number,
	userAddress: string,
	FactorSid: string
): any {
	const serviceId = "VA89bafc86dce3acce3173ae7a5cd1f5a7";

	let headers = {
		"Content-Type": "application/x-www-form-urlencoded",
		Authorization:
			"Basic QUNiMDdiY2VhNWRhZjYyYTlkOWVkNGEyYWEyM2M2YWY3YzozM2FhNDY3NmFiYzA5YWVlMzQxNmY0MjdkOTQ3ZjkzZg==",
	};

	let queryString = `AuthPayload=${otp}&FactorSid=${FactorSid}`;

	const body = stringToHex(queryString);

	let response = pink.batchHttpRequest(
		[
			{
				url: `https://verify.twilio.com/v2/Services/${serviceId}/Entities/${userAddress}/Challenges`,
				method: "POST",
				headers,
				body,
				returnTextBody: true,
			},
		],
		10000
	)[0];

	console.log(JSON.parse(response.body as string));

	if (![200, 201].includes(response.statusCode)) {
		console.log(
			`OTP Status: ${response.statusCode}, error: ${
				response.error || response.body
			}}`
		);
		throw Error.FailedToFetchData;
	}
	let respBody = response.body;
	if (typeof respBody !== "string") {
		throw Error.FailedToDecode;
	}

	const parsedBody = JSON.parse(respBody);

	if (parsedBody.status === "pending") {
		return 0;
	} else if (parsedBody.status === "approved") {
		return 1;
	} else {
		throw Error.ErrorWhileParse;
	}
}

function isHexString(str: string): boolean {
	const regex = /^0x[0-9a-f]+$/;
	return regex.test(str.toLowerCase());
}

function parseHex(hexx: string): string {
	var hex = hexx.toString();
	if (!isHexString(hex)) {
		throw Error.FailedToDecode;
	}
	hex = hex.slice(2);
	var str = "";
	for (var i = 0; i < hex.length; i += 2) {
		const ch = String.fromCharCode(parseInt(hex.substring(i, i + 2), 16));
		str += ch;
	}
	return str;
}

export default function main(request: HexString): HexString {
	console.log(`handle req: ${request}`);
	let requestId, otpHash, userAddress, factorHash;
	try {
		[requestId, otpHash, userAddress, factorHash] = Coders.decode(
			[uintCoder, uintCoder, bytesCoder, bytesCoder],
			request
		);
	} catch (error) {
		console.info("Malformed request received");
		return encodeReply([
			TYPE_ERROR,
			requestId,
			errorToCode(error as Error),
		]);
	}

	try {
		requestId = parseInt(requestId);
		otpHash = parseInt(otpHash);
		userAddress = parseHex(userAddress);
		factorHash = parseHex(factorHash);

		console.log(`requestId: ${requestId}`);
		console.log(`otpHash: ${otpHash}`);
		console.log(`userAddress: ${userAddress}`);
		console.log(`factorHash: ${factorHash}`);
	} catch (error) {
		return encodeReply([
			TYPE_ERROR,
			requestId,
			errorToCode(error as Error),
		]);
	}

	try {
		const factor = getFactor(factorHash);
		console.log(`Factor is ${factor}`);

		const bool = checkAuthyOTP(otpHash, userAddress, factor);
		console.log(`checkOTP function returned: ${bool}`);

		return encodeReply([TYPE_RESPONSE, requestId, bool]);
	} catch (error) {
		console.log("error:", [TYPE_ERROR, requestId, error]);
		return encodeReply([
			TYPE_ERROR,
			requestId,
			errorToCode(error as Error),
		]);
	}
}
