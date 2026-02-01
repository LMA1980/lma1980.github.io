# LMA1980

I will use this Github page to document the incubator project I am hoping to conceive.

## Jelo-Mu

An incubator project for a distributed application model, I will attempt to write it in Rust or in C#, and any other appropriate language to work with this solution.

The idea, is to provide a solution to normalize the compute logic between the various runtime environment the application will interact with.
- Client layer:
   - Web: Html + Javascript + Css + WASM (WASI Component)[API client]
   - GUI: <Framework> + WASM (WASI Component)[API client]
   - both: Support OpenTelemetry
- Backend layer:
   - OAuth X.x authentication mechanism
   - Role based access control
### Idea's for the backend layer:
1. Shared queues/messages with multi-tenancy support
2. Use Rust+Apache Fory to create a distributed shared memory system 
   - [mem-cluster][tenant][mem-addr][fory blob][with role access policy]
   - support mutliple protocol: http2, http3, raw socket, GRPC...
   - the memory doesn't exists necessarily on the same host
   - support transaction
3. Support OpenTelemetry
4. A Role Policy management system
   - cluster-wide policy: useful for system operator
     - client-side
     - backend-side
   - tenant-wide policy: useful for tenant operator
     - client-side
     - backend-side 
   - feature policy: provided by engineer, engineer may define policy that apply to cluster-wide capability or tenant-wide capability.
