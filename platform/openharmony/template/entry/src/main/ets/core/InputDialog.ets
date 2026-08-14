/**************************************************************************/
/*  InputDialog.ets                                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

import plugin from 'libentry.so';

@CustomDialog
@Component
export struct InputDialogContent {
  @State textValue: string = ''
  @Prop title: string = ''
  @Prop message: string = ''
  @Prop defaultText: string = ''
  controller?: CustomDialogController

  aboutToAppear() {
    this.textValue = this.defaultText
  }

  build() {
    Column({ space: $r('sys.float.ohos_id_elements_margin_vertical_l') }) {
      Text(this.title)
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontWeight(FontWeight.Bold)
        .fontSize($r('sys.float.ohos_id_text_size_headline8'))
        .margin($r('sys.float.ohos_id_elements_margin_vertical_m'))

      TextInput({ placeholder: this.message, text: this.textValue })
        .width('100%')
        .onChange((value: string) => {
          this.textValue = value
        })

      Row({ space: $r('sys.float.ohos_id_elements_margin_horizontal_m') }) {
        Button($r('sys.string.general_cancel'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            if (this.controller != undefined) {
              this.controller.close()
            }
          })

        Divider()
          .vertical(true)
          .height($r('sys.float.ohos_id_text_paragraph_margin_l'))

        Button($r('sys.string.general_confirm'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.brand'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            plugin.inputDialogResult(this.textValue)
            if (this.controller != undefined) {
              this.controller.close()
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding($r('sys.float.ohos_id_elements_margin_vertical_l'))
  }
}
