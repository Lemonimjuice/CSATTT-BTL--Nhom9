# Temporary HTTP gateway for Backend V2 tests

`Test-V2Host.ps1` merges `docker-compose.sqli-lab.test.yml` after the existing lab Compose. The override is only for the disposable test project. The base lab Compose, schema, JWT contract, endpoints and TV1/TV2 infrastructure are unchanged.

```text
Windows 127.0.0.1:<random port>
             |
      sqli-test-gateway ------ private test edge bridge
             |
      internal sqli-lab-net
        |         |         |
     lab API   identity DB  fixture DB
```

The override resets the API's ports with Compose `!reset []`. Only the gateway joins both networks and publishes `127.0.0.1::8080`. API and both PostgreSQL services remain on exactly the internal network, with no requested or active host bindings. Neither network is external or shared with business services. The gateway has no DB/JWT credentials, Docker socket, dynamic destination or routing configuration.

The gateway is a plain HTTP reverse proxy with a fixed upstream `sqli-lab-api:8080`. It forwards the original HTTP request/body/Authorization and backend status. Access logging is disabled, it runs as uid/gid 101, drops all capabilities, uses a read-only filesystem and a temporary `/tmp`. It contains no ModSecurity/CRS, blocking rules or WAF response marker and provides no evidence of WAF protection.

Before Maven/HTTP tests, the runner validates effective configuration and actual Docker network membership. Only the gateway may be on the test edge; all lab services must have no direct port request/binding. Gateway binding must have exactly one active IPv4 loopback endpoint with a valid nonzero port. The runner probes real lab health through that endpoint, then runs PostgreSQL-backed Maven tests and the existing secure/lab HTTP plus two-node checks.

The Maven test container separately joins the default bridge to download dependencies and the lab network to run fixture tests. It does not serve HTTP, publish ports, or join the test edge. It is removed before the project cleanup. Project networks/containers, generated backend image and labeled builder are removed by the runner; pulled shared base images may remain as cache. No business volume, container or network is touched.

`Test-LabTestGateway.ps1` validates the merged Compose without Engine access and rejects nine unsafe mutations, including direct API publishing, DB edge membership, public gateway binds, an extra business network, an external edge network, disabled internal isolation and fixed host ports. `Test-DockerLoopback.ps1` covers active-binding validation. Tests require Compose support for `!reset`; unsupported versions fail config validation before resources are created.

This test harness proves HTTP/auth/search behavior and direct backend node survival. Nginx load-balancer failover and ModSecurity integration remain TV1/TV2 acceptance tests. Actual execution evidence is stored separately under ignored `backend/logs/`.

## Verified execution — 2026-10-27

Docker Engine 29.9.2 / Compose v5.6.1, project `tv3v2e5e683feb2bd`: full host runner exited 0. Gateway's active binding was `127.0.0.1:55879`; the lab API and both DBs had no requested or active published ports and remained internal-only. Only the gateway joined the project edge. Real lab health through the gateway returned UP, without a WAF marker.

Maven: 39 tests, 0 failures, 0 errors, 0 skipped, including 5 real PostgreSQL fixture/privilege tests. HTTP secure/lab: 30 cases passed, including separate lab register/login, cross-environment JWT rejection, normal search returning 1 fixture, Boolean SQLi returning 3 fixtures, forbidden table/catalog reads, missing JWT and invalid input. Two-node run `cdd1b3a4906f49219de382f6f314ca2d`: 12 HTTP API assertions passed plus both startup health checks; cross-node JWT/Record, ownership 403, Node1 stop and Node2 health/read all passed.

Cleanup succeeded and follow-up scoped inventories confirmed no test containers, networks, volumes or generated images remain. Shared pulled base images were retained as cache. The first gateway startup exposed Nginx default temp paths on the read-only filesystem; all temp paths were moved into `/tmp` tmpfs, and `nginx -t` passed under the same non-root/read-only restrictions before the successful run. No application Java, schema, JWT contract or endpoint was changed.

Evidence: `backend/logs/v2-gateway-e2e-190bc19c793341c28a1f75e177376528.log` and `backend/logs/two-node-check-cdd1b3a4906f49219de382f6f314ca2d.log`. These are runtime results, not a claim of production WAF or Nginx load-balancer acceptance.
