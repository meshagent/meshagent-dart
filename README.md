# [Meshagent](https://www.meshagent.com)

# MeshAgent Dart

MeshAgent is your platform to create, deploy, and manage AI agents collaboratively and at scale, securely and in real time. 

MeshAgent removes the infrastructure headaches of building and shipping AI Agents. It spins up secure, real-time "Rooms" that connect humans, agents, and shared context -- letting you launch, share, and refine agents in hours instead of weeks.

---

**Documentation**: [docs.meshagent.com](https://docs.meshagent.com/)

**Website**: [www.meshagent.com](https://www.meshagent.com/)

**MeshAgent Studio**: [www.studio.meshagent.com](https://studio.meshagent.com/)

---

## Why MeshAgent? 

- **Real-time multi-user "Rooms" for true human-AI teamwork**: Secure workspaces, "Rooms", automatically spin-up when someone joins, tracking presence, chat, documents, and agent activity, and disappear when everyone leaves -- so people and agents stay in sync. 

- **Accelerated feedback loop and shortened development cycle**: Invite a colleague or stakeholder into the MeshAgent Studio Room so they can see, hear, and interact with your agent immediately -- letting you demo, gather feedback, and iterate on the agent on the same day.

- **Shareable links that showcase your agent**: After you deploy an agent, MeshAgent provides you a URL so colleagues or customers can jump straight into the Room, try the agent, and give feedback -- no code checkout, IDE, or GPU required. 

- **Reusable and extensibly agent tools**: MeshAgent ships prebuilt, reusable toolkits for common Room interactions (e.g., file and document handling, media generation, dynamic UI interactions) and high-demand tasks (e.g., web search or document-to-Markdown conversion). Support for custom tools and the Model Context Protocol (MCP) enables you to seamlessly integrate any MCP-compatible service into a Room without changes to your applications. Tools are centrally managed like agents, allowing you to deploy them once and reuse them effortlessly.

- **Built-in Observability**: Streaming logs and traces give you real-time insight into every message, agent action, and error. 

- **Secure and elastic by default**: Project-scoped keys, on-demand provisioning, and auto-scaling infrastructure keep Rooms private, secure, and ready for your usage needs.

- **Support across languages**: The same feature set (Rooms, Agents, Tools, Messaging, Queues, Storage, Documents, etc.) is exposed through official Python, Javascript, Typescript, and Dart SDKs, so every team member can work in their preferred language. 


## Getting Setup

Follow our [Getting Started Documentation](https://docs.meshagent.com/introduction/get_started) to setup your MeshAgent account, create your first project, and start building agents!

## Next Steps and Examples

To see examples of agents in action and to start building your own agents check out the MeshAgent docs at [docs.meshagent.com](https://docs.meshagent.com/)

## Anonymous website connections

On a website bound to a room, use the existing client
with anonymous authorization:

```dart
import 'package:meshagent/meshagent.dart';

final room = RoomClient.withAnonymous();
await room.start();
```

Grant the resource an appropriate IAM role for `everyone:all` first. The default
authorization URL is `/.well-known/meshagent/authorize` on the current website.
Pass an absolute `authorizationUrl` when running outside a browser.

Each initial connection and reconnect obtains a fresh token before opening the
WebSocket. The anonymous cookie preserves the visitor identity; token expiration
does not interrupt an open connection. Browsers retain the HttpOnly cookie across
visits. Native clients retain it within the provider instance. Removing the browser
cookie or creating a new native provider starts a new anonymous identity.

For custom authentication, supply `tokenProvider` to `WebSocketClientProtocol`.
Use an `AccessTokenProvider` in Dart. The provider is called on every connection attempt and replaces the static token.
`AnonymousAccessTokenProvider` is also available for explicit reuse and exposes
`expiresAt` after a successful exchange. Keep one provider for a native session.

Anonymous authorization failures include the server's denial reason. The token
provider's exceptions expose `statusCode` and `errorCode`, which are also retained
when initial connection is denied. Denial uses
`anonymous_access_denied`, other HTTP failures use
`anonymous_authorization_failed`, and malformed success responses use
`invalid_anonymous_authorization_response`. Connection failures during refresh
retain the reason in the existing connection lifecycle notifications. A denied
refresh stops automatic retries; transient failures retain the usual retry behavior.
