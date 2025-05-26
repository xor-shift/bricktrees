source bench_defs.nu

let schema = "
CREATE TABLE backends (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  bpa             INTEGER NOT NULL,
  tree_breadth    INTEGER DEFAULT NULL,
  tree_curve      TEXT DEFAULT NULL CHECK(tree_curve IN ('raster', 'llm1')),
  manually_cached INTEGER DEFAULT null
);

INSERT INTO backends VALUES (1,  3, NULL, NULL,     NULL);
INSERT INTO backends VALUES (2,  4, NULL, NULL,     NULL);
INSERT INTO backends VALUES (3,  5, NULL, NULL,     NULL);
INSERT INTO backends VALUES (4,  6, NULL, NULL,     NULL);
INSERT INTO backends VALUES (5,  3, 8,    'raster', 0);
INSERT INTO backends VALUES (6,  4, 8,    'raster', 0);
INSERT INTO backends VALUES (7,  5, 8,    'raster', 0);
INSERT INTO backends VALUES (8,  6, 8,    'raster', 0);
INSERT INTO backends VALUES (9,  3, 8,    'llm1',   0);
INSERT INTO backends VALUES (10, 4, 8,    'llm1',   0);
INSERT INTO backends VALUES (11, 5, 8,    'llm1',   0);
INSERT INTO backends VALUES (12, 6, 8,    'llm1',   0);
INSERT INTO backends VALUES (13, 3, 8,    'llm1',   1);
INSERT INTO backends VALUES (14, 4, 8,    'llm1',   1);
INSERT INTO backends VALUES (15, 5, 8,    'llm1',   1);
INSERT INTO backends VALUES (16, 6, 8,    'llm1',   1);
INSERT INTO backends VALUES (17, 4, 64,   'raster', 0);
INSERT INTO backends VALUES (18, 6, 64,   'raster', 0);
INSERT INTO backends VALUES (19, 8, 64,   'raster', 0);
INSERT INTO backends VALUES (20, 4, 64,   'llm1',   0);
INSERT INTO backends VALUES (21, 6, 64,   'llm1',   0);
INSERT INTO backends VALUES (22, 8, 64,   'llm1',   0);

CREATE TABLE scenes (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  filename  TEXT,
  width     INTEGER,
  height    INTEGER,
  depth     INTEGER,
  center_x  REAL,
  center_y  REAL,
  center_z  REAL
);

CREATE TABLE benchmarks (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  scene_id INTEGER,
  pos_x    REAL,
  pos_y    REAL,
  pos_z    REAL,
  yaw      REAL,
  pitch    REAL,
  width    INTEGER DEFAULT 1280,
  height   INTEGER DEFAULT 720,

  FOREIGN KEY(scene_id) REFERENCES scenes(id)
);

CREATE TABLE measurements (
  benchmark_id   INTEGER,
  backend_id     INTEGER,
  card           TEXT     CHECK(card IN ('nvidia', 'amd')),
  measurement_no INTEGER,
  measurement    REAL,

  FOREIGN KEY(backend_id) REFERENCES backends(id)
);

CREATE TABLE memory_stats (
  benchmark_id      INTEGER,
  backend_id        INTEGER,
  used_brickmaps    INTEGER,
  total_brickmaps   INTEGER,
  brickgrid_entries INTEGER,

  FOREIGN KEY(backend_id) REFERENCES backends(id),
  FOREIGN KEY(benchmark_id) REFERENCES benchmarks(id)
);
";

let resolution = [1920 1080];

def main [out_sqlite: string] {
  try { mv $out_sqlite $"($out_sqlite).old" } catch {}
  $schema | sqlite3 $out_sqlite;

  $scenes | enumerate | rename --column { index: scene_id } | flatten | each { |v|
    $"INSERT INTO scenes VALUES \(($v.scene_id), '($v.file)', ($v.dims.0), ($v.dims.1), ($v.dims.2), ($v.center.0), ($v.center.2), ($v.center.2)\)" | sqlite3 $out_sqlite;
  };

  let benchmarks = $benchmarks | enumerate | rename --column { index: benchmark_id } | flatten;

  $benchmarks | each { |v|
    $"INSERT INTO benchmarks VALUES \(($v.benchmark_id), ($v.scene_no), ($v.pos.0), ($v.pos.1), ($v.pos.2), ($v.look.0), ($v.look.1), ($resolution.0), ($resolution.1)\)" | sqlite3 $out_sqlite;
  };

  0..(($benchmarks | length) - 1) | each { |benchmark_no|
    let benchmark = $benchmarks | get $benchmark_no;
    let backends_to_test = open $out_sqlite | query db $"select id from backends where bpa <= ($benchmark.bpa_upto)" | get id;

    $backends_to_test | each { |backend|
      let res_amd = run_bench "amd" $benchmark_no $backend $resolution;
      let res_nvidia = run_bench "nvidia" $benchmark_no $backend $resolution;

      [
        ["nvidia" ($res_nvidia | get measurements | enumerate)]
        ["amd" ($res_amd | get measurements | enumerate)]
      ] | each { |v| $v.1 | each { |w|
        $"INSERT INTO measurements VALUES \(($benchmark_no), ($backend), '($v.0)', ($w.index), ($w.item)\)" | sqlite3 $out_sqlite;
      }};

      $"INSERT INTO memory_stats VALUES \(($benchmark_no), ($backend), ($res_nvidia.stats.used_brickmaps | into int), ($res_nvidia.stats.total_brickmaps | into int), ($res_nvidia.stats.brickgrid_entries | into int)\)" | sqlite3 $out_sqlite;
    }
  }
}
