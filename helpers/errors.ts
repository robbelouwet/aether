export const errTypes = {
  revert: "revert",
};

export async function tryCatch(promise: Promise<any>, reason: string) {
  try {
    const tx = await promise;
    await tx.wait(); // 🔴 REQUIRED
    throw new Error("Expected revert not received");
  } catch (error: any) {
    if (!error.message.includes(reason)) {
      throw error;
    }
  }
}
