# Smoke test: boots the app (Bandit on :8000) and exercises key endpoints.
alias BaconNet.{E, Kbinxml}

# Build a kbin services.get request like a game would send
req =
  E.e("call", E.e("services", method: "get"),
    model: "LDJ:J:A:A:2025091700",
    srcid: "X000000001"
  )

File.write!("/tmp/smoke_services.kbin", Kbinxml.encode(req))

# cardmng getrefid + inquire
req2 =
  E.e("call", E.e("cardmng", nil, method: "getrefid", cardid: "E004010203040506", passwd: "1234"),
    model: "LDJ:J:A:A:2025091700",
    srcid: "X000000001"
  )

File.write!("/tmp/smoke_getrefid.kbin", Kbinxml.encode(req2))

req3 =
  E.e("call", E.e("cardmng", nil, method: "inquire", cardid: "E004010203040506"),
    model: "LDJ:J:A:A:2025091700",
    srcid: "X000000001"
  )

File.write!("/tmp/smoke_inquire.kbin", Kbinxml.encode(req3))

# facility get
req4 =
  E.e("call", E.e("facility", nil, method: "get"),
    model: "LDJ:J:A:A:2025091700",
    srcid: "X000000001"
  )

File.write!("/tmp/smoke_facility.kbin", Kbinxml.encode(req4))
IO.puts("request fixtures written")
