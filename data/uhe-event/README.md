# KM3NeT UHE event KM3-230213A

This folder bundles a single KM3NeT open-data event so that the RainbowAlga
documentation (and anyone who installs the package) can render a real, physically
meaningful event out of the box.

## Files

- `KM3-230213A_allhits.root` -- the event in the native KM3NeT offline ROOT format,
  containing the reconstructed muon track and the photon hits on the individual PMTs.
- `detector.dynamical.datx` -- the corresponding (dynamically calibrated) detector
  geometry used to position the optical modules and calibrate the hits.

## The event

KM3-230213A is the ultra-high-energy neutrino event detected by KM3NeT/ARCA on
2023-02-13 at 01:16:47 UTC, with a reconstructed muon energy in the ~100 PeV range. It
is described in

> The KM3NeT Collaboration, *Observation of an ultra-high-energy cosmic neutrino with
> KM3NeT*, Nature 638, 376-382 (2025).
> https://www.nature.com/articles/s41586-024-08543-1

## Provenance and license

Both files are copied verbatim from the KM3NeT open-data repository

> https://git.km3net.de/open-data/public-candidates/uhe-event

(`data/event/KM3-230213A_allhits.root` and
`data/supplementary/detector/detector.dynamical.datx` therein).

They are redistributed here under their original BSD 3-Clause license,
Copyright (c) 2025, The KM3NeT collaboration. See the accompanying `LICENSE` file.
