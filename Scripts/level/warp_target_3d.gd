extends Marker3D
class_name WarpTarget3D

## Punto de destino para cualquier warp (local o externo). Además de la
## posición/orientación (heredadas de Marker3D), permite indicar a qué
## CameraZone3D pertenece este punto para que la GameCamera se asiente ahí
## de forma INSTANTÁNEA en el momento del warp, en vez de esperar a que la
## detección física de la Area3D la alcance un frame después (lo que se
## vería como un deslizamiento de cámara justo cuando arranca el fade-in).
##
## Asigná 'camera_zone' siempre que este punto quede dentro de una
## CameraZone3D, que va a ser el caso casi siempre.

@export var camera_zone: CameraZone3D
