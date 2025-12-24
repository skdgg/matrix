import numpy as np
import matplotlib.pyplot as plt
import os
import sys
from tqdm import tqdm

# ==========================================
# 1. 基礎數學與矩陣函式
# ==========================================

def make_translation_matrix(tx, ty, tz):
    return np.array([
        [1, 0, 0, tx],
        [0, 1, 0, ty],
        [0, 0, 1, tz],
        [0, 0, 0, 1]
    ])

def make_scale_matrix(sx, sy, sz):
    return np.array([
        [sx, 0, 0, 0],
        [0, sy, 0, 0],
        [0, 0, sz, 0],
        [0, 0, 0, 1]
    ])

def make_rotation_y_matrix(degrees):
    radians = np.radians(degrees)
    cos_a = np.cos(radians)
    sin_a = np.sin(radians)
    return np.array([
        [cos_a, 0, sin_a, 0],
        [0,     1, 0,     0],
        [-sin_a,0, cos_a, 0],
        [0,     0, 0,     1]
    ])

def normalize(v):
    norm = np.sqrt(v @ v)
    if norm == 0: return v
    return v / norm

# ==========================================
# 2. Rasterizer (光柵化器) - 核心新增部分
# 參考: Gabriel Gambetta - Computer Graphics from Scratch (Ch 6, 7, 8)
# ==========================================

class Rasterizer:
    def __init__(self, width, height):
        self.width = int(width)
        self.height = int(height)
        # 建立畫布: Height x Width x 3 (RGB), 數值範圍 0.0 ~ 1.0
        self.canvas = np.zeros((self.height, self.width, 3))

    def put_pixel(self, x, y, color):
        # 為了安全起見檢查邊界 (雖然演算法應確保在範圍內)
        x = int(round(x))
        y = int(round(y))
        if 0 <= x < self.width and 0 <= y < self.height:
            self.canvas[y, x] = color

    def interpolate(self, i0, d0, i1, d1):
        """
        線性插值: 計算從 i0 到 i1 之間，變數 d 的變化
        回傳一個陣列，包含每一步的 d 值
        參考: https://gabrielgambetta.com/computer-graphics-from-scratch/06-lines.html
        """
        if i0 == i1:
            return np.array([d0])
        
        # 使用 numpy linspace 替代迴圈以提升 Python 效能
        # 包含端點，這與教學中的迴圈邏輯一致
        return np.linspace(d0, d1, int(i1 - i0 + 1))

    def draw_line(self, p0, p1, color):
        """
        畫線 (Bresenham's algorithm 概念的插值實作)
        p0, p1: (x, y) tuple
        參考: https://gabrielgambetta.com/computer-graphics-from-scratch/06-lines.html
        """
        x0, y0 = int(round(p0[0])), int(round(p0[1]))
        x1, y1 = int(round(p1[0])), int(round(p1[1]))

        if abs(x1 - x0) > abs(y1 - y0):
            # Line is horizontal-ish
            if x0 > x1: x0, y0, x1, y1 = x1, y1, x0, y0
            ys = self.interpolate(x0, y0, x1, y1)
            for i, x in enumerate(range(x0, x1 + 1)):
                self.put_pixel(x, ys[i], color)
        else:
            # Line is vertical-ish
            if y0 > y1: x0, y0, x1, y1 = x1, y1, x0, y0
            xs = self.interpolate(y0, x0, y1, x1)
            for i, y in enumerate(range(y0, y1 + 1)):
                self.put_pixel(xs[i], y, color)

    def draw_shaded_triangle(self, p0, p1, p2, color):
        """
        畫填滿且有陰影的三角形 (Gouraud Shading 概念)
        p0, p1, p2: (x, y, h) tuple，其中 h 為亮度強度 (0~1)
        參考: https://gabrielgambetta.com/computer-graphics-from-scratch/08-shaded-triangles.html
        """
        # 1. 依照 Y 座標排序頂點: P0 (底), P1 (中), P2 (頂)
        # 注意：这里的 Y 是螢幕座標，通常 Y=0 在上方，但我們的 Canvas 處理時會對應好
        pts = sorted([p0, p1, p2], key=lambda p: p[1])
        x0, y0, h0 = pts[0]
        x1, y1, h1 = pts[1]
        x2, y2, h2 = pts[2]

        y0, y1, y2 = int(round(y0)), int(round(y1)), int(round(y2))
        
        # 避免退化三角形 (面積為 0)
        if y0 == y2: return 

        # 2. 計算三角形三邊的 X 座標與 亮度 H 的插值陣列
        # 長邊: 0 -> 2
        x02 = self.interpolate(y0, x0, y2, x2)
        h02 = self.interpolate(y0, h0, y2, h2)
        
        # 短邊 1: 0 -> 1
        x01 = self.interpolate(y0, x0, y1, x1)
        h01 = self.interpolate(y0, h0, y1, h1)
        
        # 短邊 2: 1 -> 2
        x12 = self.interpolate(y1, x1, y2, x2)
        h12 = self.interpolate(y1, h1, y2, h2)

        # 3. 組合短邊數據以符合長邊的長度
        # 注意: interpolate 包含端點，所以接合處要去掉一個重複點
        x012 = np.concatenate([x01[:-1], x12])
        h012 = np.concatenate([h01[:-1], h12])

        # 確保長度一致 (因浮點數轉整數可能會有 1 pixel 誤差)
        m = len(x02)
        x012 = x012[:m]
        h012 = h012[:m]

        # 4. 判斷哪一邊是左邊，哪一邊是右邊
        mid = len(x02) // 2
        if x02[mid] < x012[mid]:
            x_left, h_left = x02, h02
            x_right, h_right = x012, h012
        else:
            x_left, h_left = x012, h012
            x_right, h_right = x02, h02

        # 5. 逐行掃描 (Scanline)
        for i in range(len(x_left)):
            y = y0 + i
            # 如果超出畫布範圍則跳過
            if y < 0 or y >= self.height: continue

            xl = int(round(x_left[i]))
            xr = int(round(x_right[i]))
            
            hl = h_left[i]
            hr = h_right[i]

            # 繪製水平線段 (Horizontal Segment)
            if xr > xl:
                # 計算這一段水平線上的亮度變化
                h_segment = self.interpolate(xl, hl, xr, hr)
                
                # 裁切螢幕範圍 (Clipping X)
                start_x = max(0, xl)
                end_x = min(self.width, xr + 1) # Python slice is exclusive at end
                
                # 如果被裁切掉則不畫
                if start_x < end_x:
                    # 計算裁切後的亮度陣列對應部分
                    seg_idx_start = start_x - xl
                    seg_idx_end = seg_idx_start + (end_x - start_x)
                    current_h = h_segment[seg_idx_start:seg_idx_end]
                    
                    # 顏色混合 (Base Color * Intensity)
                    # 利用 numpy 廣播機制一次填滿整條線
                    pixel_colors = color * current_h[:, np.newaxis]
                    
                    self.canvas[y, start_x:end_x] = pixel_colors

# ==========================================
# 3. Vertex Pipeline (來自 HackMD)
# ==========================================
"""
Input:  V[x, y, z]
        N[nx, ny, nz]
        M_MV: 4*4 Model View matrix
        P_scale_x/y: projection scale
Output: Px, Py, inv_Pz, Brightness
"""

def vertex_processing_pipeline(V, N, M_MV, P_scale_x, P_scale_y):
    # 1. 頂點座標變換 V' = M_MV * V
    V_prime = M_MV @ V
    V_prime_xyz = V_prime[0:3]

    # 2. 光照向量計算
    L_p_prime = L_p - V_prime_xyz

    # 3. 向量正規化
    N_transformed = M_MV[:3, :3] @ N 
    N_hat = normalize(N_transformed)
    L_p_prime_hat = normalize(L_p_prime)
    L_d_hat = normalize(L_d)

    # 4. 漫反射強度計算
    I_diffuse_p = max(0.0, np.dot(N_hat, L_p_prime_hat))
    I_diffuse_d = max(0.0, np.dot(N_hat, L_d_hat))

    # 5. 最終亮度輸出
    brightness = (I_diffuse_p * L_p_intensity) + \
                 (I_diffuse_d * L_d_intensity) + \
                 L_a_intensity
    brightness = min(1.0, brightness) # Clamp 避免過曝

    # 6. 座標輸出
    V_z_prime = V_prime[2]
    dist_sq = V_z_prime * V_z_prime
    inv_Pz = 0 if dist_sq < 1e-9 else 1.0 / np.sqrt(dist_sq)

    # 投影變換 Px, Py (原點在中心)
    P_x = V_prime[0] * P_scale_x * inv_Pz
    P_y = V_prime[1] * P_scale_y * inv_Pz

    return P_x, P_y, inv_Pz, brightness

# ==========================================
# 4. OBJ Loader
# ==========================================
# load v, vn, f
def load_obj(filename):
    triangles = []
    raw_vertices = []
    raw_normals = []
    
    try:
        with open(filename, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if not parts: continue
                if parts[0] == 'v':
                    raw_vertices.append(np.array([float(parts[1]), float(parts[2]), float(parts[3]), 1.0]))
                elif parts[0] == 'vn':
                    raw_normals.append(np.array([float(parts[1]), float(parts[2]), float(parts[3])]))
                elif parts[0] == 'f':
                    face_indices = []
                    for p in parts[1:]:
                        vals = p.split('/')
                        v_idx = int(vals[0]) - 1
                        n_idx = int(vals[2]) - 1 if len(vals) > 2 and vals[2] else -1
                        face_indices.append((v_idx, n_idx))
                    for i in range(1, len(face_indices) - 1):
                        tri_verts = [face_indices[0], face_indices[i], face_indices[i+1]]
                        current_tri = []
                        for v_idx, n_idx in tri_verts:
                            v = raw_vertices[v_idx]
                            n = raw_normals[n_idx] if n_idx >= 0 and n_idx < len(raw_normals) else np.array([0.0, 1.0, 0.0]) 
                            current_tri.append((v, n))
                        triangles.append(current_tri + ['gold']) # 顏色暫存
        print(f"Loaded {len(triangles)} triangles.")
        return triangles
    except FileNotFoundError:
        print(f"Error: File {filename} not found.")
        return []
    
def normalize_model(triangles):
    """
    將模型的所有頂點歸一化：
    1. 計算中心點並移回原點 (Centering)
    2. 縮放至 [-1, 1] 範圍 (Scaling)
    這樣可以確保模型一定會出現在相機前方，且大小適中。
    """
    # 收集所有頂點座標
    all_vertices = []
    for t in triangles:
        # t[0], t[1], t[2] 是 (v, n) tuple，我們只需要 v
        all_vertices.append(t[0][0][:3]) # 取 x,y,z
        all_vertices.append(t[1][0][:3])
        all_vertices.append(t[2][0][:3])
    
    vertices_np = np.array(all_vertices)
    
    # 1. 計算中心並位移
    centroid = np.mean(vertices_np, axis=0)
    
    # 2. 計算最大半徑 (Scale)
    # 找出離中心最遠的點，將其距離設為縮放基準
    distances = np.linalg.norm(vertices_np - centroid, axis=1)
    max_dist = np.max(distances)
    scale_factor = 1.0 / max_dist
    
    print(f"Model Centroid: {centroid}, Max Scale: {max_dist}")

    # 更新所有三角形的頂點數據
    new_triangles = []
    for t in triangles:
        # t = [(v1, n1), (v2, n2), (v3, n3), color]
        new_tri = []
        for i in range(3):
            v, n = t[i]
            # 更新頂點位置: (v - centroid) * scale
            v_new_xyz = (v[:3] - centroid) * scale_factor
            v_new = np.array([v_new_xyz[0], v_new_xyz[1], v_new_xyz[2], 1.0])
            new_tri.append((v_new, n))
        
        # 補上顏色
        new_tri.append(t[3])
        new_triangles.append(new_tri)
        
    return new_triangles

# ==========================================
# 5. Main Loop: Render & Rasterize 分離
# ==========================================

class Model:
    def __init__(self, triangles):
        self.triangles = triangles # list of [(v1, n1), (v2, n2), (v3, n3), color_str]

class Instance:
    def __init__(self, model, position, scale=1.0, rotation_y=0):
        self.model = model
        m_scale = make_scale_matrix(scale, scale, scale)
        m_rot = make_rotation_y_matrix(rotation_y)
        m_trans = make_translation_matrix(*position)
        self.transform_matrix = m_trans @ m_rot @ m_scale

class Camera:
    def __init__(self, position, rotation_y):
        self.position = position
        self.rotation_y = rotation_y
    def get_view_matrix(self):
        m_trans_inv = make_translation_matrix(-self.position[0], -self.position[1], -self.position[2])
        m_rot_inv = make_rotation_y_matrix(-self.rotation_y)
        return m_rot_inv @ m_trans_inv

def hex_to_rgb(hex_color):
    if not isinstance(hex_color, str):
        return np.array(hex_color)

    # 原本的字典邏輯
    colors = {
        'gold':  np.array([1.0, 0.84, 0.0]),
        'red':   np.array([1.0, 0.0, 0.0]),
        'green': np.array([0.0, 1.0, 0.0]),
        'blue':  np.array([0.0, 0.0, 1.0]),
        'gray':  np.array([0.5, 0.5, 0.5]),
        # 你也可以在這裡加新顏色
    }
    return colors.get(hex_color, np.array([1.0, 1.0, 1.0]))

def render_scene(camera, instances, width, height):
    rasterizer = Rasterizer(width, height)
    M_view = camera.get_view_matrix()
    
    # === 修正 1: 保持長寬比 ===
    # 使用相同數值，避免畫面拉伸變形
    scale = min(width, height) / 2.0
    P_SCALE_X = scale
    P_SCALE_Y = scale # 確保正方形像素

    OFFSET_X = width / 2
    OFFSET_Y = height / 2

    print("Rendering...")

    # 收集場景中所有要畫的三角形 (用於排序)
    render_list = []

    for instance in instances:
        M_MV = M_view @ instance.transform_matrix
        
        for tri in tqdm(instance.model.triangles, desc='Vertex processing'):
            v_data = tri[:3]
            color_name = tri[3]
            base_color = hex_to_rgb(color_name)

            avg_z = 0.0
            temp_raster_points = []
            valid_triangle = True
            
            for v, n in v_data:
                # Vertex Pipeline
                px, py, inv_pz, bright = vertex_processing_pipeline(v, n, M_MV, P_SCALE_X, P_SCALE_Y)
                
                # 簡單 Clipping
                V_prime = M_MV @ v
                if V_prime[2] >= -0.1: 
                     valid_triangle = False
                
                avg_z += V_prime[2]
                screen_x = OFFSET_X + px
                screen_y = OFFSET_Y - py 
                temp_raster_points.append((screen_x, screen_y, bright))

            if valid_triangle:
                avg_z /= 3.0
                render_list.append({
                    'z': avg_z,
                    'points': temp_raster_points,
                    'color': base_color
                })

    # === 修正 2: 畫家演算法 (Painter's Algorithm) ===
    # 根據 Z 值排序：由小到大 (因為相機看向 -Z，越小的負數越遠)
    # 如果你的相機座標系不同，可能需要改為 reverse=True
    render_list.sort(key=lambda x: x['z']) 

    # 開始rasterize
    for item in tqdm(render_list, desc="Rasterization"):
        p0, p1, p2 = item['points']
        color = item['color']
        rasterizer.draw_shaded_triangle(p0, p1, p2, color)

    return rasterizer.canvas

# ==========================================
# 6. 執行
# ==========================================

CANVAS_WIDTH = 640
CANVAS_HEIGHT = 480

# 全域光照與投影設定
L_p = np.array([0.0, 10.0, 0])    # 點光源
L_p_intensity = 1
L_d = np.array([0.0, 0.0, 1.0])   # 方向光
L_d_intensity = 0.4
L_a_intensity = 0.2               # 環境光

scale = 1.3
view_angle = 30
instance_position = (0, 0, 0)
camera_position = (0, 0, 2)
color = 'red'
# color = np.array([0.3, 0.3, 0.3]) # [r,g,b] 0.0 ~ 1.0

if __name__ == "__main__":
    # inputs model name
    if len(sys.argv) > 1:
        model_name = sys.argv[1]
    
    # load obj model
    model_dir = './models'
    model_file = model_name + '.obj'
    os.makedirs(model_dir, exist_ok=True)
    model_path = os.path.join(model_dir, model_file)

    triangles = load_obj(model_path)
    
    if triangles:
        # 1. 正規化模型 (重要!)
        normalized_triangles = normalize_model(triangles)
        for tri in normalized_triangles:
            tri[3] = color
        norm_model = Model(normalized_triangles)

        # 2. 設定相機
        camera = Camera(position=camera_position, rotation_y=0) 
        
        # 3. 建立實例
        instances = [
            Instance(norm_model, position=instance_position, scale=scale, rotation_y=view_angle) 
        ]

        # render and rasterize
        final_image = render_scene(camera, instances, CANVAS_WIDTH, CANVAS_HEIGHT)

        # outputs
        output_dir = './outputs'
        os.makedirs(output_dir, exist_ok=True)
        output_file = model_name + '.jpg'
        output_path = os.path.join(output_dir, output_file)
        plt.imsave(output_path, final_image)
        print(f"Render finished. Image saved to: {output_path}")
    else:
        print("Model not loaded.")
