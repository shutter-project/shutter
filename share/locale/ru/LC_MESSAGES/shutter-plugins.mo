��    E      D  a   l      �  	   �     �  .   �  5   -  #   c  &   �  #   �     �  �   �  "   ~  ,   �     �     �     �     �     �     �               .  #   B  1   f     �     �      �  
   �  4   �     	  	   	     	     "	     A	     P	  [   _	     �	     �	  H   �	  
   
     
     =
     F
     S
  
   q
     |
     �
  *   �
  (   �
     �
  	     "        ;  
   A     L  	   ]  
   g     r          �  t  �  T     (   [     �     �  2   �  M   �  	        !  �   '  �  �     �     �  d   �  E     $   W  L   |  U   �  2     �   R  =     [   E  	   �     �     �  -   �     �  
   �      �  "     &   B  ^   i  t   �     =     A  4   N     �  �   �           6     R  2   h  
   �  
   �  �   �     a     p  |        �  F        Y  !   j  ?   �     �     �  *   �  X   (  T   �  A   �       3   (  
   \  
   g     r     �     �     �     �     �  �  �  �   �  J        e     z  ]   �  �   �          �  p  �               (          !          A   ;              E   0           8   ,                                    +         .   D       C   =       #   :   *         6      /      "   5      %   <   @                                     7   &          3   >   2       	       ?               
      '              )   $          B      9      -       1   4       3D rotate A: Add a custom text watermark to your screenshot Add a shadow to the image on a transparent background Add a torn-like border to the image Add an inverted 3d border to the image Add sepia color toning to the image Add soft edges around the image Applies a perspective distortion to an image

Based on a script by Fred Weinhaus

http://www.fmwconcepts.com/imagemagick/3Drotate/index.php Applies a simple reflection effect Apply a distortion effect to your screenshot Auto: B: Background color Barrel Distortion C: Channel Choose background color Choose sky color Choose stroke color Cut a jigsaw piece out of the image Cut out a jigsaw piece at the bottom right corner D: Effect Error while executing plugin %s. Font size: Give the picture an offset with itself as background Gravity: Grayscale Hard Shadow Invert the colors of the image Jigsaw Piece 1 Jigsaw Piece 2 Make your screenshot look like a polaroid photo, add a caption, and even rotate it a little Negate Offset Output zoom factor; where value > 1 means zoom in and < 1 means zoom out PDF Export Perspective exaggeration factor Polaroid Raise Border Raise a rectangular 3d-border Reflection Resize Resize your screenshot Rotation about image horizontal centerline Rotation about image vertical centerline Rotation about the image center Rotation: Save your screenshot as a PDF file Sepia Sepia tone Shutter Branding Sky color Soft Edges Stroke color Sunk Border Text: The parameter d describes the linear scaling of the image. Using d=1, and a=b=c=0 leaves the image as it is. Choosing other d-values scales the image by that amount. a,b and c distort the image. Using negative values shifts distant points away from the center.

Defined by Barrel Correction Distortion, by Helmut Dersch.
http://www.all-in-one.ee/~dersch/barrel/barrel.html There are several wild-cards available, like
%Y = year
%m = month
%d = day
%T = time There was an error executing the plugin. Tool Torned Paper Turn the image into a grayscale image (256 shades) Turn the image into a polaroid one with the Shutter logo and a subtitle added Watermark Zoom: off - No automatic adjustment

c - Center bounding box in output

zc - Zoom to fill and center bounding box in output

out - Creates an output image of size needed to hold the transformed image Project-Id-Version: gscrot-plugins-bash
Report-Msgid-Bugs-To: FULL NAME <EMAIL@ADDRESS>
POT-Creation-Date: 2009-11-29 11:29+0100
PO-Revision-Date: 2009-12-24 10:22+0000
Last-Translator: Photon <michael.kogan@gmx.net>
Language-Team: Russian <ru@li.org>
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit
X-Launchpad-Export-Date: 2010-03-15 23:56+0000
X-Generator: Launchpad (build Unknown)
 3D поворот А: Добавить собственный текстовый водяной знак на снимок Четкая черная тень на прозрачном фоне Создает рваный край Создает утопленную прямоугольную 3D рамку Подцветка изображения в мягкий коричневый тон Скругляет углы изображения Перспективное искажение снимка\n
\n
Основано на скрипте Fred Weinhaus'а\n
\n
http://www.fmwconcepts.com/imagemagick/3Drotate/index.php Создает простой эффект отражения Применить эффект искривления на выбранный снимок Авто: Б: Цвет фона Бочкообразные искажения В: Канал Выбрать цвет фона Выберите цвет неба Выберите цвет штриха Вырезает кусочек мозайки пазл из всего изображения Вырезает в нижнем правом углу изображения кусочек мозайки пазл Г: Эффект Ошибка выполнения плагина %s. Размер шрифта: Создает вокруг изображения рамку с самим изображением в качестве фона Гравитация: Оттенки серого Четкая тень Инвертировать цвета снимка Пазл 1 Пазл 2 Преобразование снимка в формат \"полароид\", добавление надписи и небольшой поворот изображения Негатив Позиция Изменение масштаба, где z > 1 обозначает увеличение, а z < 1 - уменьшение Экспорт в PDF Коэффициент перспективного искажения Полароид Выступающая рамка Выступающая прямоугольная 3D рамка Отражение Изменить размер Изменить размер снимка Вращение вокруг горизонтальной оси изображения Вращение вокруг вертикальной оси изображения Вращение вокруг центра изображения Поворот: Сохранить снимок как файл PDF Сепия Сепия Штамп Shutter Цвет неба Мягкие углы Цвет штриха Утопленная рамка Текст: Параметр d описывает линейное масштабирование изображения. Использование d=1 и a =b=c=0 оставляет изображение как есть. Выбор других значений d масштабирует изображение на это значение. a, b и c искажают изображение. Использование отрицательных значений сдвигает далекие точки от центра.

Определение из Коррекции бочкообразных искажений, Helmut Dersch.
http://www.all-in-one.ee/~dersch/barrel/barrel.html Вы можете использовать следующие маски:
%Y = год
%m = месяц
%d = день
%T = время Произошла ошибка при выполнении плагина Инструмент Рваная бумага Создает изображение в оттенках серого (256 оттенков) Создает карточку полароид с логотипом Shutter и именем файла в качестве надписи Водяной знак Масштаб: off - Без пересчета размеров

c - Центрировать изображение и обрезать по размеру рамки

zc - Центрировать изображение и вписать в размеры рамки

out - Увеличить рамку до размеров преобразованного изображение 