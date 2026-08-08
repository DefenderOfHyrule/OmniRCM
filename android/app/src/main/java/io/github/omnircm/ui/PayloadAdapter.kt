package io.github.omnircm.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.RadioButton
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import io.github.omnircm.R
import io.github.omnircm.data.Payload

class PayloadAdapter(
    private val onSelected: (Payload) -> Unit,
    private val onRename: ((Payload) -> Unit)? = null,
    private val onDelete: ((Payload) -> Unit)? = null,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private sealed class Item {
        data class Header(val label: String) : Item()
        data class Entry(val payload: Payload, val index: Int) : Item()
    }

    private var items: List<Item> = emptyList()
    private var allPayloads: List<Payload> = emptyList()
    private var selectedPayloadIndex = -1

    fun submit(list: List<Payload>) {
        allPayloads = list
        val built = mutableListOf<Item>()
        val remote = list.filter { !it.isCustom }
        val custom = list.filter { it.isCustom }
        var idx = 0
        remote.forEach { built.add(Item.Entry(it, idx++)) }
        if (custom.isNotEmpty()) {
            built.add(Item.Header("Custom"))
            custom.forEach { built.add(Item.Entry(it, idx++)) }
        }
        items = built
        notifyDataSetChanged()
    }

    fun getSelected(): Payload? = allPayloads.getOrNull(selectedPayloadIndex)

    fun selectIndex(index: Int) {
        val prev = selectedPayloadIndex
        selectedPayloadIndex = index
        notifyDataSetChanged()
    }

    override fun getItemViewType(position: Int) = when (items[position]) {
        is Item.Header -> 0
        is Item.Entry  -> 1
    }

    inner class HeaderViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val label: TextView = view.findViewById(R.id.header_label)
    }

    inner class EntryViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val radio:        RadioButton = view.findViewById(R.id.payload_radio)
        val name:         TextView    = view.findViewById(R.id.payload_name)
        val version:      TextView    = view.findViewById(R.id.payload_version)
        val renameButton: ImageButton = view.findViewById(R.id.btn_rename_payload)
        val deleteButton: ImageButton = view.findViewById(R.id.btn_delete_payload)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == 0) {
            HeaderViewHolder(inflater.inflate(R.layout.item_payload_header, parent, false))
        } else {
            EntryViewHolder(inflater.inflate(R.layout.item_payload, parent, false))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val item = items[position]) {
            is Item.Header -> (holder as HeaderViewHolder).label.text = item.label
            is Item.Entry  -> {
                holder as EntryViewHolder
                val payload = item.payload
                val index   = item.index
                holder.name.text    = payload.name
                holder.radio.isChecked = index == selectedPayloadIndex

                if (payload.isCustom) {
                    holder.version.text       = "custom"
                    holder.version.visibility = View.VISIBLE
                } else if (payload.version != null) {
                    holder.version.text       = "v${payload.version}"
                    holder.version.visibility = View.VISIBLE
                } else {
                    holder.version.visibility = View.GONE
                }

                val click = View.OnClickListener {
                    val prev = selectedPayloadIndex
                    selectedPayloadIndex = index
                    notifyDataSetChanged()
                    onSelected(payload)
                }
                holder.itemView.setOnClickListener(click)
                holder.radio.setOnClickListener(click)

                if (payload.isCustom && onRename != null) {
                    holder.renameButton.visibility = View.VISIBLE
                    holder.renameButton.setOnClickListener { onRename.invoke(payload) }
                } else {
                    holder.renameButton.visibility = View.GONE
                }

                if (payload.isCustom && onDelete != null) {
                    holder.deleteButton.visibility = View.VISIBLE
                    holder.deleteButton.setOnClickListener { onDelete.invoke(payload) }
                } else {
                    holder.deleteButton.visibility = View.GONE
                }
            }
        }
    }

    override fun getItemCount() = items.size
}
