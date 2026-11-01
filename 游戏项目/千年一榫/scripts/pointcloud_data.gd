class_name PointCloudData
extends Resource
## 点云数据资源：离线采样产物，供图鉴/结算/成功动画消费。

@export var points: PackedVector3Array = PackedVector3Array()
@export var colors: PackedColorArray = PackedColorArray()
@export var aabb_center: Vector3 = Vector3.ZERO
@export var aabb_size: Vector3 = Vector3.ONE
