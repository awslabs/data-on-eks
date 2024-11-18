import React from "react";
import Footer from "@theme-original/Footer";

export default function FooterWrapper(props) {
  return (
    <>
      <Footer {...props} />
      <script
        defer
        src='https://static.cloudflareinsights.com/beacon.min.js'
        data-cf-beacon='{"token": "7fbc7ab02fae4767b1af2588eba0cdf2"}'
      ></script>
    </>
  );
}
