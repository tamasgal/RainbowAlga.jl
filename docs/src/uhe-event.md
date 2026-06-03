```@meta
CurrentModule = RainbowAlga
```

# The KM3-230213A ultra-high-energy event

RainbowAlga ships with one real KM3NeT open-data event so you can produce a physically
meaningful display without hunting for data first. **KM3-230213A** is the
ultra-high-energy neutrino detected by KM3NeT/ARCA on 2023-02-13, with a reconstructed
muon energy of about 120 PeV (corresponding to an inferred neutrino energy of around
220 PeV); it is described in
[*Observation of an ultra-high-energy cosmic neutrino with KM3NeT*](https://www.nature.com/articles/s41586-024-08543-1)
(Nature **638**, 376-382, 2025).

The event and its detector geometry live in `data/uhe-event/` and are redistributed under
their original BSD 3-Clause license; see `data/uhe-event/README.md` for the provenance and
a link to the [open-data repository](https://git.km3net.de/open-data/public-candidates/uhe-event).

Every figure below is rendered at documentation build time with [`snapshot`](@ref), which
draws the scene off-screen (no window opens), so the exact same code produces these images
on a headless machine under `xvfb-run`.

## A first look

Wrapping the ROOT file and the detector in an [`EventFile`](@ref) and handing it to
[`load!`](@ref) is all it takes: the geometry is drawn, the photon hits become a
time-coloured cloud and the reconstructed muon is added together with its Cherenkov cone.

```@example uhe
using RainbowAlga, KM3io

datadir = joinpath(pkgdir(RainbowAlga), "data", "uhe-event")
f = EventFile(joinpath(datadir, "KM3-230213A_allhits.root"),
              joinpath(datadir, "detector.dynamical.datx"))

rba = RBA()        # an empty display
load!(rba, f)      # detector + first event (hits, reconstructed muon, Cherenkov cone)

snapshot(rba, "uhe_simple.png"; size = (1000, 750), time = 2200,
         eyeposition = (391.5, 1411.7, 1127.7), lookat = (73.0, 323.8, 380.1))
nothing # hide
```

![A first look at KM3-230213A](uhe_simple.png)

`time = 2200` freezes the animation 2200 ns after the first hit -- late enough for the
muon and its light front to cross the detector. Drop the keyword to show the fully
developed event, or lower it to watch the Cherenkov cone sweep through.

## A publication-quality figure

For a cleaner figure we keep only the first few hits on each PMT with
[`select_first_hits`](@ref), colour them by their Cherenkov time residual with respect to
the muon using [`generate_colors`](@ref) -- hits compatible with the Cherenkov hypothesis
are highlighted in cyan -- and apply the colours with [`recolor!`](@ref).

```@example uhe
using ColorSchemes

detector = Detector(joinpath(datadir, "detector.dynamical.datx"))
event = first(ROOTFile(joinpath(datadir, "KM3-230213A_allhits.root")).offline)
muon = bestjppmuon(event)
hits = select_first_hits(event.hits; n = 5, maxtot = 256)

rba = RBA()
update!(rba, detector)
add!(rba, hits; hit_distance = 3)
add!(rba, muon)                       # the muon track and its Cherenkov cone

t₀ = muon.t + 800
recolor!(rba, 1, generate_colors(muon, hits; cherenkov_thresholds = (-5, 25),
                                 t₀ = t₀, timespan = 1800, cmap = ColorSchemes.thermal))
rba.simparams.t_offset = t₀

snapshot(rba, "uhe_event.png"; size = (1000, 750), hit_scaling = 10, time = 1800,
         eyeposition = (391.5, 1411.7, 1127.7), lookat = (73.0, 323.8, 380.1))
nothing # hide
```

![KM3-230213A coloured by Cherenkov time residual](uhe_event.png)

Figure 1 of the discovery paper uses three camera angles -- a `front`, a `top` and a
`zoom` view. Here is the same scene from the close-up perspective:

```@example uhe
snapshot(rba, "uhe_closeup.png"; size = (1000, 750), hit_scaling = 10, time = 1800,
         eyeposition = (392.9, 634.0, 449.7), lookat = (70.4, 392.8, 284.1))
nothing # hide
```

![Close-up of the hit pattern](uhe_closeup.png)

A camera you have lined up interactively can be stored with [`save_perspective`](@ref) and
recalled with [`load_perspective`](@ref) (or the number keys), and passed straight to
`snapshot` via the `perspective` keyword.

## Annotating the event

[`annotate!`](@ref) adds your own primitives or text labels on top of a scene. They honour
the same colours and transparency as any Makie mesh, so a translucent sphere is a handy
way to mark a region of interest (pass `transparency = true` for correct blending of
overlapping transparent objects):

```@example uhe
p = muon.pos + muon.dir * 300         # 300 m along the muon track
annotate!(rba.scene, p, :Sphere; size = 60, color = :deepskyblue,
          alpha = 0.25, transparency = true)
annotate!(rba.scene, (p[1], p[2], p[3] + 90), "region of interest"; fontsize = 26)

snapshot(rba, "uhe_annotated.png"; size = (1000, 750), hit_scaling = 10, time = 1800,
         eyeposition = (392.9, 634.0, 449.7), lookat = (70.4, 392.8, 284.1))
nothing # hide
```

![The event with a translucent marker and a label](uhe_annotated.png)
