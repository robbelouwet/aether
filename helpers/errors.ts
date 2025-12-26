import { assert } from "chai";

const PREFIX = "Returned error: VM Exception while processing transaction: ";

export const errTypes = {
  revert: "revert",
  outOfGas: "out of gas",
  invalidJump: "invalid JUMP",
  invalidOpcode: "invalid opcode",
  stackOverflow: "stack overflow",
  stackUnderflow: "stack underflow",
  staticStateChange: "static state change",
} as const;

type ErrType = (typeof errTypes)[keyof typeof errTypes];

/**
 * Wrap a promise and assert that it throws an expected error type.
 * @param promise The promise to test (typically a contract call)
 * @param errType The expected error type
 */
export async function tryCatch(promise: Promise<any>, errType: ErrType): Promise<void> {
  try {
    await promise;
    throw new Error("Expected an error but the promise resolved successfully");
  } catch (error: any) {
    assert(error, "Expected an error but did not get one");

    // Use optional chaining for safety
    const message = error?.message || "";
    assert(
      message.startsWith(PREFIX + errType),
      `Expected an error starting with '${PREFIX + errType}' but got '${message}' instead`,
    );
  }
}
