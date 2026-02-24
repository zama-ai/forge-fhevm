import { defineConfig } from "vitepress";

export default defineConfig({
  title: "forge-fhevm",
  description:
    "Foundry-native testing library for FHEVM confidential smart contracts",
  cleanUrls: true,

  head: [
    [
      "meta",
      {
        property: "og:description",
        content:
          "Test FHEVM confidential contracts in Foundry with real host contracts, plaintext tracking, and EIP-712 proof generation.",
      },
    ],
  ],

  themeConfig: {
    nav: [
      { text: "Guide", link: "/getting-started" },
      { text: "API Reference", link: "/api/fhevm-test" },
      {
        text: "GitHub",
        link: "https://github.com/zama-ai/forge-fhevm",
      },
    ],

    sidebar: [
      {
        text: "Introduction",
        items: [
          { text: "Getting Started", link: "/getting-started" },
        ],
      },
      {
        text: "Guides",
        items: [
          { text: "Encrypt Inputs", link: "/guides/encrypt-inputs" },
          { text: "Decrypt Results", link: "/guides/decrypt-results" },
          {
            text: "Testing Patterns",
            link: "/guides/testing-patterns",
          },
        ],
      },
      {
        text: "API Reference",
        items: [
          { text: "FhevmTest", link: "/api/fhevm-test" },
          { text: "InputProofHelper", link: "/api/input-proof-helper" },
          {
            text: "KMSDecryptionProofHelper",
            link: "/api/kms-decryption-proof-helper",
          },
          {
            text: "UserDecryptHelper",
            link: "/api/user-decrypt-helper",
          },
        ],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/zama-ai/forge-fhevm" },
    ],

    search: {
      provider: "local",
    },

    footer: {
      message: "Released under the BSD-3-Clause-Clear License.",
      copyright: "Copyright 2024-present Zama",
    },
  },
});
