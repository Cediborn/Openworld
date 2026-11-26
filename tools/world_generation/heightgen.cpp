// Openworld offline heightmap generator, built on FastNoise2 (MIT).
//
// Reads a region from regions.cfg, builds that region's FastNoise2 node graph,
// samples it on a grid and writes:
//   <out>/<region>.r16   16-bit little-endian heights (0..65535 = height_min..height_max)
//   <out>/<region>.json  size, spacing and height range, for the Godot import step
//
// The same region name and seed always give the same file (strict floating
// point is enabled in CMakeLists.txt). The noise is only the foundation:
// rivers, waterfalls, ponds and landmarks are sculpted on top by the Godot
// import script (tools/world_generation/build_terrain.gd), so regenerating
// never erases a hand-designed place.
#include <FastNoise/FastNoise.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

using Cfg = std::map<std::string, std::string>;

static std::map<std::string, Cfg> read_cfg(const std::string& path) {
    std::map<std::string, Cfg> out;
    std::ifstream f(path);
    std::string line, section;
    while (std::getline(f, line)) {
        auto hash = line.find('#');
        if (hash != std::string::npos) line = line.substr(0, hash);
        line.erase(0, line.find_first_not_of(" \t\r"));
        line.erase(line.find_last_not_of(" \t\r") + 1);
        if (line.empty()) continue;
        if (line.front() == '[' && line.back() == ']') { section = line.substr(1, line.size() - 2); continue; }
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string k = line.substr(0, eq), v = line.substr(eq + 1);
        k.erase(k.find_last_not_of(" \t") + 1);
        v.erase(0, v.find_first_not_of(" \t"));
        out[section][k] = v;
    }
    return out;
}

static float num(const Cfg& c, const char* k, float def) {
    auto it = c.find(k);
    return it == c.end() ? def : std::stof(it->second);
}

static FastNoise::SmartNode<> fbm(float scale, int octaves, float gain) {
    auto simplex = FastNoise::New<FastNoise::SuperSimplex>();
    simplex->SetScale(scale);
    auto f = FastNoise::New<FastNoise::FractalFBm>();
    f->SetSource(simplex);
    f->SetOctaveCount(octaves);
    f->SetGain(gain);
    return f;
}

static FastNoise::SmartNode<> ridged(float scale, int octaves) {
    auto simplex = FastNoise::New<FastNoise::SuperSimplex>();
    simplex->SetScale(scale);
    auto f = FastNoise::New<FastNoise::FractalRidged>();
    f->SetSource(simplex);
    f->SetOctaveCount(octaves);
    return f;
}

static FastNoise::SmartNode<> warp(FastNoise::SmartNode<> src, float amp, float scale) {
    auto w = FastNoise::New<FastNoise::DomainWarpSimplex>();
    w->SetSource(src);
    w->SetWarpAmplitude(amp);
    w->SetScale(scale);
    return w;
}

static FastNoise::SmartNode<> add(FastNoise::SmartNode<> a, FastNoise::SmartNode<> b, float bw) {
    auto m = FastNoise::New<FastNoise::Multiply>();
    m->SetLHS(b);
    m->SetRHS(bw);
    auto s = FastNoise::New<FastNoise::Add>();
    s->SetLHS(a);
    s->SetRHS(m);
    return s;
}

// One graph per landscape type; feature sizes in metres.
static FastNoise::SmartNode<> recipe(const std::string& name, const Cfg& c) {
    float scale = num(c, "feature_size", 200.0f);
    if (name == "rolling_hills")   // Hub Meadow, the green valley: soft, warped hills
        return warp(add(fbm(scale, 3, 0.35f), fbm(scale * 0.3f, 2, 0.5f), 0.12f), scale * 0.06f, scale * 2.0f);
    if (name == "mountains")       // Frost Peaks: sharp ridges over broad massifs
        return warp(add(ridged(scale, 6), fbm(scale * 2.0f, 3, 0.5f), 0.6f), scale * 0.15f, scale * 1.5f);
    if (name == "volcanic") {      // Ember Wastes: craters (cellular pits) and lava ridges
        auto cell = FastNoise::New<FastNoise::CellularDistance>();
        cell->SetScale(scale * 0.6f);
        return add(ridged(scale, 4), cell, 0.8f);
    }
    if (name == "hollow") {        // Glow Hollow: terraced shelves and odd stone outcrops
        auto t = FastNoise::New<FastNoise::Terrace>();
        t->SetSource(warp(fbm(scale, 4, 0.5f), scale * 0.4f, scale));
        t->SetStepCount(6.0f);
        t->SetSmoothness(0.4f);
        return t;
    }
    if (name == "farmland") {      // Brickton: wide, gently tilted fields between low hills
        return add(fbm(scale * 2.0f, 3, 0.4f), fbm(scale * 0.5f, 2, 0.5f), 0.08f);
    }
    std::cerr << "unknown recipe " << name << "\n";
    std::exit(2);
}

int main(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "usage: heightgen <regions.cfg> <region> <out_dir>\n";
        return 1;
    }
    auto all = read_cfg(argv[1]);
    std::string region = argv[2];
    if (!all.count(region)) { std::cerr << "no region [" << region << "]\n"; return 1; }
    const Cfg& c = all[region];
    int size = (int)num(c, "size", 512);
    float spacing = num(c, "spacing", 1.0f);
    int seed = (int)num(c, "seed", 1337);
    float hmin = num(c, "height_min", 0.0f), hmax = num(c, "height_max", 60.0f);
    auto gen = recipe(c.at("recipe"), c);

    std::vector<float> v((size_t)size * size);
    auto mm = gen->GenUniformGrid2D(v.data(), 0.0f, 0.0f, size, size, spacing, spacing, seed);
    // Normalise to 0..1 with an optional curve (>1 flattens lowlands, sharpens peaks).
    float curve = num(c, "curve", 1.0f);
    std::vector<uint16_t> out(v.size());
    for (size_t i = 0; i < v.size(); i++) {
        float t = (v[i] - mm.min) / std::max(mm.max - mm.min, 1e-6f);
        t = std::pow(std::clamp(t, 0.0f, 1.0f), curve);
        out[i] = (uint16_t)std::lround(t * 65535.0f);
    }
    std::string dir = argv[3];
    std::ofstream r(dir + "/" + region + ".r16", std::ios::binary);
    for (uint16_t h : out) { char b[2] = {(char)(h & 0xff), (char)(h >> 8)}; r.write(b, 2); }
    std::ofstream j(dir + "/" + region + ".json");
    j << "{\"region\": \"" << region << "\", \"size\": " << size << ", \"spacing\": " << spacing
      << ", \"height_min\": " << hmin << ", \"height_max\": " << hmax << ", \"seed\": " << seed
      << ", \"recipe\": \"" << c.at("recipe") << "\"}\n";
    std::cout << "wrote " << dir << "/" << region << ".r16 (" << size << "x" << size << ", " << hmin << ".." << hmax << " m)\n";
    return 0;
}
